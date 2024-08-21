// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IAtomicSolver } from "../IAtomicSolver.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";

interface IAtomicQueue {
    function solve(
        ERC20 offer,
        ERC20 want,
        address[] calldata users,
        bytes calldata runData,
        address solver
    )
        external;
}

contract MultiAssetAtomicSolverBase is IAtomicSolver, Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /**
     * @notice The Solve Type, used in `finishSolve` to determine the logic used.
     * @notice P2P Solver wants to swap share.asset() for user(s) shares
     * @notice REDEEM Solver needs to redeem shares, then can cover user(s) required assets.
     * for this solver to be compatible with first two versions of queue, this is needed to be able to encode the data
     * only redeem is used in this solver
     */
    enum SolveType {
        P2P,
        REDEEM
    }

    //============================== ERRORS ===============================

    error MultiAssetAtomicSolverRedeem___WrongInitiator();
    error MultiAssetAtomicSolverRedeem___AlreadyInSolveContext();
    error MultiAssetAtomicSolverRedeem___FailedToSolve();
    error MultiAssetAtomicSolverRedeem___SolveMaxAssetsExceeded(uint256 actualAssets, uint256 maxAssets);
    error MultiAssetAtomicSolverRedeem___BoringVaultTellerMismatch(address vault, address teller);
    error MultiAssetAtomicSolverRedeem___InsufficientAssetsRedeemed(uint256 redeemedAmount, uint256 requiredAmount);
    error MultiAssetAtomicSolverRedeem___MismatchedArrayLengths();
    error MultiAssetAtomicSolverRedeem___DuplicateOrUnsortedAssets();

    // Updated struct to hold data for each want asset
    struct WantAssetData {
        ERC20 asset; // The desired asset by the users
        uint256 minimumAssetsOut; // a slippage control at the asset level
        uint256 maxAssets; // the maximum amount of assets to be redeemed for this asset
        // the amount of assets that will be redeemed in excess of user redemptions (can be 0)
        uint256 excessAssetAmount;
        // if true, will use all the initial solver balance in that asset first
        bool useSolverBalanceFirst;
        address[] users;
    }

    constructor(address _owner) Auth(_owner, Authority(address(0))) { }

    //============================== SOLVE FUNCTIONS ===============================

    /**
     * @notice This function is used to solve for multiple assets in a single transaction
     * @param queue the AtomicQueueV2 contract
     * @param offer the ERC20 asset sent to the solver
     * @param wantAssets an array of WantAssetData structs, each containing the desired asset and its users
     * @param maxOfferAssets the maximum amount of offer assets that can be used in this transaction
     * @param teller the TellerWithMultiAssetSupport contract
     * @param globalSlippagePriceMinimum the global slippage price minimum
     */
    function multiAssetRedeemSolve(
        IAtomicQueue queue,
        ERC20 offer,
        WantAssetData[] calldata wantAssets,
        uint256 maxOfferAssets,
        TellerWithMultiAssetSupport teller,
        int256 globalSlippagePriceMinimum
    )
        external
        requiresAuth
    {
        AccountantWithRateProviders accountant = teller.accountant();
        uint256 totalOfferNeeded = 0;
        uint256[] memory assetPrices = new uint256[](wantAssets.length);

        uint256 previousAssetAddress = 0;

        for (uint256 i = 0; i < wantAssets.length; i++) {
            // Check if assets are in increasing order (prevents duplicates)
            uint256 currentAssetAddress = uint256(uint160(address(wantAssets[i].asset)));
            if (currentAssetAddress <= previousAssetAddress) {
                revert MultiAssetAtomicSolverRedeem___DuplicateOrUnsortedAssets();
            }
            previousAssetAddress = currentAssetAddress;

            assetPrices[i] = accountant.getRateInQuoteSafe(wantAssets[i].asset);
            if (assetPrices[i] == 0) {
                revert MultiAssetAtomicSolverRedeem___FailedToSolve();
            }
            _doTempStore(wantAssets[i].asset, wantAssets[i].excessAssetAmount, wantAssets[i].useSolverBalanceFirst);
        }

        // Solve for each want asset with its corresponding users
        for (uint256 i = 0; i < wantAssets.length; i++) {
            bytes memory runData = abi.encode(
                SolveType.REDEEM,
                msg.sender,
                wantAssets[i].minimumAssetsOut,
                wantAssets[i].maxAssets,
                teller,
                assetPrices[i]
            );
            queue.solve(offer, wantAssets[i].asset, wantAssets[i].users, runData, address(this));
        }

        // do the global slippage check with the balances, prices and maxOfferAssets...might decimal conversion?

        // send any excess offer shares to the solver
        // possibly implement a preferred redeem asset to redeem first then send?
        offer.safeTransfer(msg.sender, offer.balanceOf(address(this)));
    }

    function finishSolve(
        bytes calldata runData,
        address initiator,
        ERC20 offer,
        ERC20 want,
        uint256 offerReceived,
        uint256 wantApprovalAmount
    )
        external
        requiresAuth
    {
        if (initiator != address(this)) revert MultiAssetAtomicSolverRedeem___WrongInitiator();

        address queue = msg.sender;

        SolveType _type = abi.decode(runData, (SolveType));

        if (_type == SolveType.P2P) {
            revert MultiAssetAtomicSolverRedeem___OnlyRedeemAllowed();
        } else if (_type == SolveType.REDEEM) {
            _multiAssetRedeemSolve(queue, runData, offer, want, offerReceived, wantApprovalAmount);
        }
    }

    function _multiAssetRedeemSolve(
        address queue,
        bytes memory runData,
        ERC20 offer,
        ERC20 want,
        uint256 offerReceived,
        uint256 wantApprovalAmount
    )
        internal
    {
        (, address wantAssets, uint256 minimumAssetsOut, uint256 maxAssets, TellerWithMultiAssetSupport teller, uint256)
        = abi.decode(runData, (SolveType, address, uint256, uint256, TellerWithMultiAssetSupport, uint256));

        if (address(offer) != address(teller.vault())) {
            revert MultiAssetAtomicSolverRedeem___BoringVaultTellerMismatch(address(offer), address(teller));
        }

        // Make sure solvers `maxAssets` was not exceeded.
        if (wantApprovalAmount > maxAssets) {
            revert MultiAssetAtomicSolverRedeem___SolveMaxAssetsExceeded(wantApprovalAmount, maxAssets);
        }

        // Find from tload the excessAssetAmount and useSolverBalanceFirst for this want asset
        (uint256 excessAmount, bool useSolverBalanceFirst) = _doTempLoad(want);

        // Calculate the amount of offer asset needed for this want asset
        uint256 offerNeededForWant = (wantApprovalAmount * assetPrice) / 1e18; // Assuming 18 decimals for price

        // Redeem the shares, sending assets to solver
        teller.bulkWithdraw(want, offerNeededForWant, currentWantAsset.minimumAssetsOut, solver);

        // Transfer required assets from solver
        want.safeTransferFrom(solver, address(this), wantApprovalAmount);

        // Approve queue to spend wantApprovalAmount
        want.safeApprove(queue, wantApprovalAmount);
    }

    function _doTempStore(address asset, uint256 excessAmount, bool useSolverBalanceFirst) internal {
        // Store excessAssetAmount and useSolverBalanceFirst for each asset
        uint256 key1 = uint256(keccak256(abi.encodePacked(asset)));
        uint256 key2 = key1 + 1;

        assembly {
            tstore(key1, excessAmount)
            tstore(key2, useSolverBalanceFirst)
        }
    }

    function _doTempLoad(address asset) internal view returns (uint256, bool) {
        uint256 key1 = uint256(keccak256(abi.encodePacked(asset)));
        uint256 key2 = key1 + 1;

        uint256 excessAssetAmount;
        bool useSolverBalanceFirst;

        assembly {
            excessAssetAmount := tload(key1)
            useSolverBalanceFirst := tload(key2)
        }

        return (excessAssetAmount, useSolverBalanceFirst);
    }

    function _doTempDelete(address asset) internal {
        uint256 key1 = uint256(keccak256(abi.encodePacked(asset)));
        uint256 key2 = key1 + 1;

        assembly {
            tstore(key1, 0)
            tstore(key2, 0)
        }
    }
}
