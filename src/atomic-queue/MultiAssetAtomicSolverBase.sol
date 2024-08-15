// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AtomicQueueV2 } from "./AtomicQueueV2.sol";
import { IAtomicSolver } from "./IAtomicSolver.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";

contract MultiAssetAtomicSolverBase is IAtomicSolver, Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /**
     * @notice The Solve Type, used in `finishSolve` to determine the logic used.
     * @notice P2P Solver wants to swap share.asset() for user(s) shares
     * @notice REDEEM Solver needs to redeem shares, then can cover user(s) required assets.
     */
    enum SolveType {
        P2P,
        REDEEM
    }

    //============================== ERRORS ===============================

    error MultiAssetAtomicSolverBase___WrongInitiator();
    error MultiAssetAtomicSolverBase___AlreadyInSolveContext();
    error MultiAssetAtomicSolverBase___FailedToSolve();
    error MultiAssetAtomicSolverBase___SolveMaxAssetsExceeded(uint256 actualAssets, uint256 maxAssets);
    error MultiAssetAtomicSolverBase___P2PSolveMinSharesNotMet(uint256 actualShares, uint256 minShares);
    error MultiAssetAtomicSolverBase___BoringVaultTellerMismatch(address vault, address teller);
    error MultiAssetAtomicSolverBase___InsufficientAssetsRedeemed(uint256 redeemedAmount, uint256 requiredAmount);
    error MultiAssetAtomicSolverBase___MismatchedArrayLengths();
    error MultiAssetAtomicSolverBase___DuplicateOrUnsortedAssets();

    // Updated struct to hold data for each want asset, including its users
    struct WantAssetData {
        ERC20 asset;
        uint256 amount;
        uint256 minimumAssetsOut;
        uint256 maxAssets;
        // if false, then this solver at end will need
        // originalWantAssetSolverBalance - maxAssets to be <= finalWantAssetSolverBalance
        // if true, then this solver at end will need
        // originalWantAssetSolverBalance + maxAssets to be >= finalWantAssetSolverBalance
        bool isBalanceSolverDeltaPositive;
        address[] users;
    }

    constructor(address _owner) Auth(_owner, Authority(address(0))) { }

    //============================== SOLVE FUNCTIONS ===============================

    //TODO: Add the multiAssetp2pSolve function here
    //TODO: Think how the queue handles the decoded data... maybe we need a queue v3 or a temp store for some of the
    // data needed on the callback?

    function multiAssetRedeemSolve(
        AtomicQueueV2 queue,
        ERC20 offer,
        WantAssetData[] calldata wantAssets,
        uint256 maxOfferAssets,
        TellerWithMultiAssetSupport teller
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
                revert MultiAssetAtomicSolverBase___DuplicateOrUnsortedAssets();
            }
            previousAssetAddress = currentAssetAddress;

            assetPrices[i] = accountant.getRateInQuoteSafe(wantAssets[i].asset);
            if (assetPrices[i] == 0) {
                revert MultiAssetAtomicSolverBase___FailedToSolve();
            }
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
        if (initiator != address(this)) revert MultiAssetAtomicSolverBase___WrongInitiator();

        address queue = msg.sender;

        SolveType _type = abi.decode(runData, (SolveType));

        if (_type == SolveType.P2P) {
            //commented out until implemented
            //_p2pSolve(queue, runData, offer, want, offerReceived, wantApprovalAmount);
        }
        else if (_type == SolveType.REDEEM) {
            _multiAssetRedeemSolve(queue, runData, offer, want, offerReceived, wantApprovalAmount);
        }
    }

    //TODO: Add the _multiAssetp2pSolve function here

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
        (
            address solver,
            WantAssetData[] memory wantAssets,
            TellerWithMultiAssetSupport teller,
            uint256[] memory assetPrices,
            uint256 totalOfferNeeded
        ) = abi.decode(runData, (SolveType, address, WantAssetData[], TellerWithMultiAssetSupport, uint256[], uint256));

        if (address(offer) != address(teller.vault())) {
            revert AtomicSolverV4___BoringVaultTellerMismatch(address(offer), address(teller));
        }

        // Find the correct WantAssetData for the current want asset
        WantAssetData memory currentWantAsset;
        uint256 assetPrice;
        for (uint256 i = 0; i < wantAssets.length; i++) {
            if (wantAssets[i].asset == want) {
                currentWantAsset = wantAssets[i];
                assetPrice = assetPrices[i];
                break;
            }
        }

        require(address(currentWantAsset.asset) != address(0), "Want asset not found in input data");

        // Calculate the amount of offer asset needed for this want asset
        uint256 offerNeededForWant = (wantApprovalAmount * assetPrice) / 1e18; // Assuming 18 decimals for price

        // Redeem the shares, sending assets to solver
        teller.bulkWithdraw(want, offerNeededForWant, currentWantAsset.minimumAssetsOut, solver);

        // Transfer required assets from solver
        want.safeTransferFrom(solver, address(this), wantApprovalAmount);

        // Approve queue to spend wantApprovalAmount
        want.safeApprove(queue, wantApprovalAmount);

        // If this is the last asset being processed, return any excess offer to the vault
        if (offerReceived > totalOfferNeeded) {
            uint256 excessOffer = offerReceived - totalOfferNeeded;
            offer.safeApprove(address(teller), excessOffer);
            teller.deposit(excessOffer, address(this));
        }
    }
}
