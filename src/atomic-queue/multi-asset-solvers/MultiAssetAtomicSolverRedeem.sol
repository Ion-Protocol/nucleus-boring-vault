// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import { IAtomicSolver } from "../IAtomicSolver.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

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

contract MultiAssetAtomicSolverRedeem is IAtomicSolver, Auth {
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
    error MultiAssetAtomicSolverRedeem___DuplicateWantAsset(address wantAsset);
    error MultiAssetAtomicSolverRedeem___GlobalSlippageThresholdExceeded(
        int256 globalSlippagePriceMinimum, int256[] balanceDeltas, int256 actualSlippage
    );
    error MultiAssetAtomicSolverRedeem___OnlyRedeemAllowed();

    // Updated struct to hold data for each want asset
    struct WantAssetData {
        ERC20 asset; // The desired asset by the users
        uint256 minimumAssetsOut; // a slippage control at the asset level
        uint256 maxAssets; // the maximum amount of assets to be redeemed for this asset
        // the amount of assets that will be redeemed in excess of user redemptions (can be 0)
        uint256 excessAssetAmount;
        // if true, will use all the initial solver balance in that asset first
        bool useSolverBalanceFirst;
        bool useAsRedeemTokenForExcessOffer; // if true, will use this asset to redeem the excess offer tokens
        address[] users;
    }

    constructor(address _owner) Auth(_owner, Authority(address(0))) { }

    //============================== SOLVE FUNCTIONS ===============================

    /**
     * @notice This function is used to solve for multiple assets in a single transaction
     * @notice Solvers should order the want assets in a way that they use their own balances (if any do so) first
     * @notice and then use the excess offer tokens to redeem the remaining assets last to minimize revert chances
     * @param queue the AtomicQueueV2 contract
     * @param offer the ERC20 asset sent to the solver
     * @param wantAssets an array of WantAssetData structs, each containing the desired asset and its users
     * @param teller the TellerWithMultiAssetSupport contract
     * @param globalSlippagePriceMinimum the global slippage price minimum
     */
    function multiAssetRedeemSolve(
        IAtomicQueue queue,
        ERC20 offer,
        WantAssetData[] calldata wantAssets,
        TellerWithMultiAssetSupport teller,
        int256 globalSlippagePriceMinimum
    )
        external
        requiresAuth
    {
        AccountantWithRateProviders accountant = teller.accountant();
        _baseDecimalsTempStore(address(offer), accountant);

        (uint256[] memory assetPrices, int256[] memory balanceDeltas, address redeemCurrencyForExcessOffer) =
            _multiAssetRedeemSolveSetup(offer, wantAssets, accountant);

        // Solve for each want asset with its corresponding users
        _doAllSolves(queue, offer, wantAssets, teller, assetPrices);

        // send any excess offer shares to the solver or redeem in requested currency if specified
        if (redeemCurrencyForExcessOffer != address(0)) {
            teller.bulkWithdraw(ERC20(redeemCurrencyForExcessOffer), offer.balanceOf(address(this)), 0, msg.sender);
        } else {
            offer.safeTransfer(msg.sender, offer.balanceOf(address(this)));
        }

        // global slippage check with the balances, prices and maxOfferAssets
        _globalSlippageCheck(balanceDeltas, assetPrices, globalSlippagePriceMinimum, wantAssets, teller);

        // delete the temp storage for base decimals
        _baseDecimalsTempDelete(address(offer));
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
        uint256,
        uint256 wantApprovalAmount
    )
        internal
    {
        (, address solver,, uint256 maxAssets, TellerWithMultiAssetSupport teller, uint256 priceToCheckAtomicPrice) =
            abi.decode(runData, (SolveType, address, uint256, uint256, TellerWithMultiAssetSupport, uint256));

        if (address(offer) != address(teller.vault())) {
            revert MultiAssetAtomicSolverRedeem___BoringVaultTellerMismatch(address(offer), address(teller));
        }

        // Make sure solvers `maxAssets` was not exceeded.
        if (wantApprovalAmount > maxAssets) {
            revert MultiAssetAtomicSolverRedeem___SolveMaxAssetsExceeded(wantApprovalAmount, maxAssets);
        }

        _handleExcessOrBalanceAmounts(solver, want, offer, teller, wantApprovalAmount, priceToCheckAtomicPrice);

        // Transfer required assets from solver
        want.safeTransferFrom(solver, address(this), wantApprovalAmount);

        // Approve queue to spend wantApprovalAmount
        want.safeApprove(queue, wantApprovalAmount);
    }

    function _doTempStore(ERC20 asset, uint256 excessAmount, bool useSolverBalanceFirst) internal {
        // Store excessAssetAmount, useSolverBalanceFirst and decimals for each asset
        uint256 key1 = uint256(keccak256(abi.encodePacked(asset)));
        uint256 key2 = key1 + 1;
        uint256 key3 = key2 + 1;

        uint8 decimals = asset.decimals();

        assembly {
            tstore(key1, excessAmount)
            tstore(key2, useSolverBalanceFirst)
            tstore(key3, decimals)
        }
    }

    function _doTempLoad(address asset) internal view returns (uint256, bool, uint8) {
        uint256 key1 = uint256(keccak256(abi.encodePacked(asset)));
        uint256 key2 = key1 + 1;
        uint256 key3 = key2 + 1;

        uint256 excessAssetAmount;
        bool useSolverBalanceFirst;
        uint8 decimals;

        assembly {
            excessAssetAmount := tload(key1)
            useSolverBalanceFirst := tload(key2)
            decimals := tload(key3)
        }

        return (excessAssetAmount, useSolverBalanceFirst, decimals);
    }

    function _doTempDelete(address asset) internal {
        uint256 key1 = uint256(keccak256(abi.encodePacked(asset)));
        uint256 key2 = key1 + 1;
        uint256 key3 = key2 + 1;

        assembly {
            tstore(key1, 0)
            tstore(key2, 0)
            tstore(key3, 0)
        }
    }

    function _baseDecimalsTempStore(address offer, AccountantWithRateProviders accountant) internal {
        uint256 key = uint256(keccak256(abi.encodePacked(offer)));
        uint8 decimals = accountant.decimals();

        assembly {
            tstore(key, decimals)
        }
    }

    function _baseDecimalsTempLoad(address offer) internal view returns (uint8) {
        uint256 key = uint256(keccak256(abi.encodePacked(offer)));
        uint8 decimals;

        assembly {
            decimals := tload(key)
        }

        return decimals;
    }

    function _baseDecimalsTempDelete(address offer) internal {
        uint256 key = uint256(keccak256(abi.encodePacked(offer)));

        assembly {
            tstore(key, 0)
        }
    }

    function _getMinOfferNeededForWant(
        uint256 wantAmount,
        uint256 priceToCheckAtomicPrice,
        ERC20 offer,
        uint8 wantDecimals
    )
        internal
        view
        returns (uint256 offerNeededForWant)
    {
        // handling cases where decimals could differ between offer and want
        // use tstore/tload to avoid external calls
        // @notice: in all nucleus deployments, offer and base decimals should be same, but other want assets could have
        // different decimals
        uint8 baseDecimals = _baseDecimalsTempLoad(address(offer));
        uint256 wantAmountWithDecimals = _changeDecimals(wantAmount, wantDecimals, baseDecimals);
        offerNeededForWant = Math.ceilDiv(wantAmountWithDecimals * (10 ** baseDecimals), priceToCheckAtomicPrice);
    }

    function _globalSlippageCheck(
        int256[] memory balanceDeltas,
        uint256[] memory assetPrices,
        int256 globalSlippagePriceMinimum,
        WantAssetData[] calldata wantAssets,
        TellerWithMultiAssetSupport teller
    )
        internal
    {
        int256 actualSlippage = 0;

        AccountantWithRateProviders accountant = teller.accountant();
        ERC20 offer = ERC20(teller.vault());

        uint8 baseDecimals = _baseDecimalsTempLoad(address(offer));

        uint256 i;
        for (i; i < balanceDeltas.length;) {
            ERC20 wantAsset = wantAssets[i].asset;
            //update the balance delta to reflect the actual change in balance
            balanceDeltas[i] = int256(wantAsset.balanceOf(msg.sender)) - balanceDeltas[i];
            (,, uint8 wantDecimals) = _doTempLoad(address(wantAsset));

            // Convert balance delta to base decimals
            int256 scaledDelta = _changeDecimalsSigned(balanceDeltas[i], wantDecimals, baseDecimals);

            // Convert asset price to base decimals
            uint256 scaledPrice = _changeDecimals(assetPrices[i], wantDecimals, baseDecimals);

            // Calculate the slippage for this asset
            int256 assetSlippage = SignedMath.ternary(scaledDelta < 0, -1, int256(1))
                * int256(
                    Math.mulDiv(
                        SignedMath.abs(scaledDelta),
                        scaledPrice,
                        10 ** baseDecimals,
                        Math.Rounding.Floor // Round down for conservative estimate
                    )
                );

            actualSlippage += assetSlippage;

            // go ahead and delete the temp storage for this want asset
            _doTempDelete(address(wantAsset));

            unchecked {
                ++i;
            }
        }

        // Update the balance delta for the offer token
        balanceDeltas[i] = int256(offer.balanceOf(msg.sender)) - balanceDeltas[i];

        // Add the offer token's balance delta in terms of base token
        actualSlippage += SignedMath.ternary(balanceDeltas[balanceDeltas.length - 1] < 0, -1, int256(1))
            * int256(
                Math.mulDiv(
                    SignedMath.abs(balanceDeltas[balanceDeltas.length - 1]),
                    accountant.getRateSafe(),
                    10 ** baseDecimals,
                    Math.Rounding.Floor // Round down for conservative estimate
                )
            );

        if (globalSlippagePriceMinimum > actualSlippage) {
            revert MultiAssetAtomicSolverRedeem___GlobalSlippageThresholdExceeded(
                globalSlippagePriceMinimum, balanceDeltas, actualSlippage
            );
        }
    }

    // Helper function to change decimals similar to one in AccountantWithRateProviders
    function _changeDecimals(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals < toDecimals) {
            return amount * (10 ** (toDecimals - fromDecimals));
        } else {
            return amount / (10 ** (fromDecimals - toDecimals));
        }
    }

    // Helper function to change decimals for signed integers
    function _changeDecimalsSigned(
        int256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    )
        internal
        pure
        returns (int256)
    {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals < toDecimals) {
            return amount * int256(10 ** (toDecimals - fromDecimals));
        } else {
            return amount / int256(10 ** (fromDecimals - toDecimals));
        }
    }

    function _doAllSolves(
        IAtomicQueue queue,
        ERC20 offer,
        WantAssetData[] calldata wantAssets,
        TellerWithMultiAssetSupport teller,
        uint256[] memory assetPrices
    )
        internal
    {
        for (uint256 i = 0; i < wantAssets.length;) {
            bytes memory runData = abi.encode(
                SolveType.REDEEM,
                msg.sender,
                wantAssets[i].minimumAssetsOut,
                wantAssets[i].maxAssets,
                teller,
                assetPrices[i]
            );
            queue.solve(offer, wantAssets[i].asset, wantAssets[i].users, runData, address(this));
            unchecked {
                ++i;
            }
        }
    }

    function _multiAssetRedeemSolveSetup(
        ERC20 offer,
        WantAssetData[] calldata wantAssets,
        AccountantWithRateProviders accountant
    )
        internal
        returns (uint256[] memory, int256[] memory, address)
    {
        uint256[] memory assetPrices = new uint256[](wantAssets.length);

        // plus 1 for the offer/vault token
        int256[] memory balanceDeltas = new int256[](wantAssets.length + 1);

        // intended to use only one redemption currency
        address redeemCurrencyForExcessOffer;

        address[] memory usedAddresses = new address[](wantAssets.length);

        uint256 i;
        for (i; i < wantAssets.length;) {
            // Checks if any want assets are duplicates,
            // since typically want assets supported will be
            // in the single digits, this does not need to be optimized with bit/bloom filtering
            // and enforcing order of want assets to be increasing in address is not feasible since
            // the order of want assets needs to correspond to which use existing balance and which use excess
            for (uint256 j = 0; j < i;) {
                address wantAssetAddress = address(wantAssets[i].asset);
                if (address(wantAssetAddress) == usedAddresses[j]) {
                    revert MultiAssetAtomicSolverRedeem___DuplicateWantAsset(wantAssetAddress);
                }
                unchecked {
                    ++j;
                }
            }
            // Get the rate in quote for each want asset
            assetPrices[i] = accountant.getRateInQuoteSafe(wantAssets[i].asset);
            // if price is 0, revert as either paused, not supported, or failed to get rate
            if (assetPrices[i] == 0) {
                revert MultiAssetAtomicSolverRedeem___FailedToSolve();
            }
            //set the temp store for the want asset which will be loaded after callback
            _doTempStore(wantAssets[i].asset, wantAssets[i].excessAssetAmount, wantAssets[i].useSolverBalanceFirst);
            // This is the currency in which any excess offer tokens will be redeemed (if specified)
            if (wantAssets[i].useAsRedeemTokenForExcessOffer) {
                redeemCurrencyForExcessOffer = address(wantAssets[i].asset);
            }
            // Set initial balance to calculate global slippage later
            balanceDeltas[i] = int256(wantAssets[i].asset.balanceOf(msg.sender));
            // Update the used addresses array for duplicate checking
            usedAddresses[i] = address(wantAssets[i].asset);
            unchecked {
                ++i;
            }
        }

        // store the solver balance for the offer asset at index wantAssets.length
        balanceDeltas[i] = int256(offer.balanceOf(msg.sender));

        return (assetPrices, balanceDeltas, redeemCurrencyForExcessOffer);
    }

    function _handleExcessOrBalanceAmounts(
        address solver,
        ERC20 want,
        ERC20 offer,
        TellerWithMultiAssetSupport teller,
        uint256 wantApprovalAmount,
        uint256 priceToCheckAtomicPrice
    )
        internal
    {
        // Find from tload the excessAssetAmount, useSolverBalanceFirst, and decimals for this want asset
        (uint256 excessAmount, bool useSolverBalanceFirst, uint8 wantDecimals) = _doTempLoad(address(want));

        uint256 offerNeededForWant;

        if (useSolverBalanceFirst) {
            uint256 solverBalance = want.balanceOf(solver);
            solverBalance >= wantApprovalAmount
                ? offerNeededForWant = 0
                : offerNeededForWant = _getMinOfferNeededForWant(
                    wantApprovalAmount - solverBalance, priceToCheckAtomicPrice, offer, wantDecimals
                );
            // Redeem the shares, sending assets to solver
            teller.bulkWithdraw(want, offerNeededForWant, wantApprovalAmount - solverBalance, solver);
        } else {
            offerNeededForWant = _getMinOfferNeededForWant(
                wantApprovalAmount + excessAmount, priceToCheckAtomicPrice, offer, wantDecimals
            );
            // Redeem the shares, sending assets to solver
            teller.bulkWithdraw(want, offerNeededForWant, wantApprovalAmount + excessAmount, solver);
        }
    }
}
