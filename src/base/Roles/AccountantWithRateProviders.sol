// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";

/**
 * @title AccountantWithRateProviders
 * @custom:security-contact security@molecularlabs.io
 */
contract AccountantWithRateProviders is Auth, IRateProvider {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    // ========================================= STRUCTS =========================================

    /**
     * @param payoutAddress the address `claimFees` sends fees to
     * @param feesOwedInBase total pending fees owed in terms of base
     * @param totalSharesLastUpdate total amount of shares the last exchange rate update
     * @param highestExchangeRate the highest the exchange rate has gone
     * @param exchangeRate the current exchange rate in terms of base
     * @param allowedExchangeRateChangeUpper the max allowed change to exchange rate from an update
     * @param allowedExchangeRateChangeLower the min allowed change to exchange rate from an update
     * @param lastUpdateTimestamp the block timestamp of the last exchange rate update
     * @param isPaused whether or not this contract is paused
     * @param minimumUpdateDelayInSeconds the minimum amount of time that must pass between
     *        exchange rate updates, such that the update won't trigger the contract to be paused
     * @param managementFee the management fee
     * @param performanceFee the performance fee
     */
    struct AccountantState {
        address payoutAddress;
        uint128 feesOwedInBase;
        uint128 totalSharesLastUpdate;
        uint96 exchangeRate;
        uint96 highestExchangeRate;
        uint16 allowedExchangeRateChangeUpper;
        uint16 allowedExchangeRateChangeLower;
        uint64 lastUpdateTimestamp;
        bool isPaused;
        uint32 minimumUpdateDelayInSeconds;
        uint16 managementFee;
        uint16 performanceFee;
    }

    /**
     * @param isPeggedToBase whether or not the asset is 1:1 with the base asset
     * @param rateProvider the rate provider for this asset if `isPeggedToBase` is false
     */
    struct RateProviderData {
        bool isPeggedToBase;
        IRateProvider rateProvider;
    }

    // ========================================= STATE =========================================

    /**
     * @notice Store the accountant state in 3 packed slots.
     */
    AccountantState public accountantState;

    /**
     * @notice Maps ERC20s to their RateProviderData.
     */
    mapping(ERC20 => RateProviderData) public rateProviderData;

    //============================== ERRORS ===============================

    error AccountantWithRateProviders__UpperBoundTooSmall();
    error AccountantWithRateProviders__LowerBoundTooLarge();
    error AccountantWithRateProviders__ManagementFeeTooLarge();
    error AccountantWithRateProviders__PerformanceFeeTooLarge();
    error AccountantWithRateProviders__Paused();
    error AccountantWithRateProviders__ZeroFeesOwed();
    error AccountantWithRateProviders__OnlyCallableByBoringVault();
    error AccountantWithRateProviders__UpdateDelayTooLarge();
    error AccountantWithRateProviders__ExchangeRateAlreadyHighest();
    error AccountantWithRateProviders__InvalidTimeDelta(uint64 currentTime, uint64 proposedUpdateTime);

    //============================== EVENTS ===============================

    event Paused();
    event Unpaused();
    event DelayInSecondsUpdated(uint32 oldDelay, uint32 newDelay);
    event UpperBoundUpdated(uint16 oldBound, uint16 newBound);
    event LowerBoundUpdated(uint16 oldBound, uint16 newBound);
    event ManagementFeeUpdated(uint16 oldFee, uint16 newFee);
    event performanceFeeUpdated(uint16 oldFee, uint16 newFee);
    event PayoutAddressUpdated(address oldPayout, address newPayout);
    event RateProviderUpdated(address asset, bool isPegged, address rateProvider);
    event ExchangeRateUpdated(uint96 oldRate, uint96 newRate, uint64 currentTime);
    event FeesClaimed(address indexed feeAsset, uint256 amount);
    event HighestExchangeRateReset();
    event FeesCalculated(uint256 managementFeesOwed, uint256 performanceFeesOwed);

    //============================== IMMUTABLES ===============================

    /**
     * @notice The base asset rates are provided in.
     */
    ERC20 public immutable base;

    /**
     * @notice The decimals rates are provided in.
     */
    uint8 public immutable decimals;

    /**
     * @notice The BoringVault this accountant is working with.
     *         Used to determine share supply for fee calculation.
     */
    BoringVault public immutable vault;

    /**
     * @notice One share of the BoringVault.
     */
    uint256 internal immutable ONE_SHARE;

    constructor(
        address _owner,
        address _vault,
        address payoutAddress,
        uint96 startingExchangeRate,
        address _base,
        uint16 allowedExchangeRateChangeUpper,
        uint16 allowedExchangeRateChangeLower,
        uint32 minimumUpdateDelayInSeconds,
        uint16 managementFee,
        uint16 performanceFee
    )
        Auth(_owner, Authority(address(0)))
    {
        base = ERC20(_base);
        decimals = ERC20(_base).decimals();
        vault = BoringVault(payable(_vault));
        ONE_SHARE = 10 ** vault.decimals();
        accountantState = AccountantState({
            payoutAddress: payoutAddress,
            feesOwedInBase: 0,
            totalSharesLastUpdate: uint128(vault.totalSupply()),
            exchangeRate: startingExchangeRate,
            highestExchangeRate: startingExchangeRate,
            allowedExchangeRateChangeUpper: allowedExchangeRateChangeUpper,
            allowedExchangeRateChangeLower: allowedExchangeRateChangeLower,
            lastUpdateTimestamp: uint64(block.timestamp),
            isPaused: false,
            minimumUpdateDelayInSeconds: minimumUpdateDelayInSeconds,
            managementFee: managementFee,
            performanceFee: performanceFee
        });
    }

    // ========================================= ADMIN FUNCTIONS =========================================
    /**
     * @notice Pause this contract, which prevents future calls to `updateExchangeRate`, and any safe rate
     *         calls will revert.
     * @dev Callable by MULTISIG_ROLE.
     */
    function pause() external requiresAuth {
        accountantState.isPaused = true;
        emit Paused();
    }

    /**
     * @notice Unpause this contract, which allows future calls to `updateExchangeRate`, and any safe rate
     *         calls will stop reverting.
     * @dev Callable by MULTISIG_ROLE.
     */
    function unpause() external requiresAuth {
        accountantState.isPaused = false;
        emit Unpaused();
    }

    /**
     * @notice Update the minimum time delay between `updateExchangeRate` calls.
     * @dev There are no input requirements, as it is possible the admin would want
     *      the exchange rate updated as frequently as needed.
     * @dev Callable by OWNER_ROLE.
     */
    function updateDelay(uint32 minimumUpdateDelayInSeconds) external requiresAuth {
        if (minimumUpdateDelayInSeconds > 14 days) revert AccountantWithRateProviders__UpdateDelayTooLarge();
        uint32 oldDelay = accountantState.minimumUpdateDelayInSeconds;
        accountantState.minimumUpdateDelayInSeconds = minimumUpdateDelayInSeconds;
        emit DelayInSecondsUpdated(oldDelay, minimumUpdateDelayInSeconds);
    }

    /**
     * @notice Update the allowed upper bound change of exchange rate between `updateExchangeRateCalls`.
     * @dev Callable by OWNER_ROLE.
     */
    function updateUpper(uint16 allowedExchangeRateChangeUpper) external requiresAuth {
        if (allowedExchangeRateChangeUpper < 1e4) revert AccountantWithRateProviders__UpperBoundTooSmall();
        uint16 oldBound = accountantState.allowedExchangeRateChangeUpper;
        accountantState.allowedExchangeRateChangeUpper = allowedExchangeRateChangeUpper;
        emit UpperBoundUpdated(oldBound, allowedExchangeRateChangeUpper);
    }

    /**
     * @notice Update the allowed lower bound change of exchange rate between `updateExchangeRateCalls`.
     * @dev Callable by OWNER_ROLE.
     */
    function updateLower(uint16 allowedExchangeRateChangeLower) external requiresAuth {
        if (allowedExchangeRateChangeLower > 1e4) revert AccountantWithRateProviders__LowerBoundTooLarge();
        uint16 oldBound = accountantState.allowedExchangeRateChangeLower;
        accountantState.allowedExchangeRateChangeLower = allowedExchangeRateChangeLower;
        emit LowerBoundUpdated(oldBound, allowedExchangeRateChangeLower);
    }

    /**
     * @notice Update the management fee to a new value.
     * @dev Callable by OWNER_ROLE.
     */
    function updateManagementFee(uint16 managementFee) external requiresAuth {
        if (managementFee > 0.2e4) revert AccountantWithRateProviders__ManagementFeeTooLarge();
        uint16 oldFee = accountantState.managementFee;
        accountantState.managementFee = managementFee;
        emit ManagementFeeUpdated(oldFee, managementFee);
    }

    /**
     * @notice Update the performance fee to a new value.
     * @dev Callable by OWNER_ROLE.
     */
    function updatePerformanceFee(uint16 performanceFee) external requiresAuth {
        if (performanceFee > 0.2e4) revert AccountantWithRateProviders__PerformanceFeeTooLarge();
        uint16 oldFee = accountantState.performanceFee;
        accountantState.performanceFee = performanceFee;
        emit performanceFeeUpdated(oldFee, performanceFee);
    }

    /**
     * @notice Update the payout address fees are sent to.
     * @dev Callable by OWNER_ROLE.
     */
    function updatePayoutAddress(address payoutAddress) external requiresAuth {
        address oldPayout = accountantState.payoutAddress;
        accountantState.payoutAddress = payoutAddress;
        emit PayoutAddressUpdated(oldPayout, payoutAddress);
    }

    /**
     * @notice Update the rate provider data for a specific `asset`.
     * @dev Rate providers must return rates in terms of `base` or
     * an asset pegged to base and they must use the same decimals
     * as `asset`.
     * @dev Callable by OWNER_ROLE.
     */
    function setRateProviderData(ERC20 asset, bool isPeggedToBase, address rateProvider) external requiresAuth {
        rateProviderData[asset] =
            RateProviderData({ isPeggedToBase: isPeggedToBase, rateProvider: IRateProvider(rateProvider) });
        emit RateProviderUpdated(address(asset), isPeggedToBase, rateProvider);
    }

    /**
     * @notice Reset the highest exchange rate to the current exchange rate.
     * @dev Callable by OWNER_ROLE.
     */
    function resetHighestExchangeRate() external virtual requiresAuth {
        AccountantState storage state = accountantState;
        if (state.isPaused) revert AccountantWithRateProviders__Paused();

        if (state.exchangeRate > state.highestExchangeRate) {
            revert AccountantWithRateProviders__ExchangeRateAlreadyHighest();
        }

        state.highestExchangeRate = state.exchangeRate;

        emit HighestExchangeRateReset();
    }

    // ========================================= UPDATE EXCHANGE RATE/FEES FUNCTIONS
    // =========================================

    /**
     * @notice Updates this contract exchangeRate.
     * @dev If new exchange rate is outside of accepted bounds, or if not enough time has passed, this
     *      will pause the contract, and this function will NOT calculate fees owed.
     * @dev Callable by UPDATE_EXCHANGE_RATE_ROLE.
     */
    function updateExchangeRate(uint96 newExchangeRate, uint64 timeDeltaSeconds) external requiresAuth {
        AccountantState storage state = accountantState;
        if (state.isPaused) revert AccountantWithRateProviders__Paused();
        uint64 currentTime = uint64(block.timestamp);
        uint64 proposedUpdateTime = state.lastUpdateTimestamp + timeDeltaSeconds;

        // Check if proposed time is within acceptable threshold of current time
        // here, allowing ±1 hour deviation
        if (proposedUpdateTime > currentTime + 1 hours || proposedUpdateTime < currentTime - 1 hours) {
            revert AccountantWithRateProviders__InvalidTimeDelta(currentTime, proposedUpdateTime);
        }
        uint256 currentExchangeRate = state.exchangeRate;
        uint256 currentTotalShares = vault.totalSupply();
        if (
            proposedUpdateTime < state.lastUpdateTimestamp + state.minimumUpdateDelayInSeconds
                || newExchangeRate > currentExchangeRate.mulDivDown(state.allowedExchangeRateChangeUpper, 1e4)
                || newExchangeRate < currentExchangeRate.mulDivDown(state.allowedExchangeRateChangeLower, 1e4)
        ) {
            // Instead of reverting, pause the contract. This way the exchange rate updater is able to update the
            // exchange rate
            // to a better value, and pause it.
            state.isPaused = true;
        } else {
            // Store raw exchange rate in memory
            uint256 rawExchangeRate = newExchangeRate;
            uint256 shareSupplyToUse = currentTotalShares;

            // Use minimum between current and last update total supply
            if (state.totalSharesLastUpdate < shareSupplyToUse) {
                shareSupplyToUse = state.totalSharesLastUpdate;
            }

            // Calculate intermediate rate directly with (time-weighted) management fee
            // intermediateRate = rawRate - rawRate * (managementFee * timeDelta)/(year * 1e4)
            uint256 intermediateRate =
                rawExchangeRate - rawExchangeRate.mulDivDown(state.managementFee * timeDeltaSeconds, 365 days * 1e4);

            // Calculate management fees for accounting raw AUM and post management fee AUM
            // rawAUM = shareSupplyToUse * rawExchangeRate
            // postManagementFeeAUM = shareSupplyToUse * intermediateRate
            // managementFeesOwed = rawAUM - postManagementFeeAUM
            uint256 rawAUM = shareSupplyToUse.mulDivDown(rawExchangeRate, ONE_SHARE);
            uint256 postManagementFeeAUM = shareSupplyToUse.mulDivDown(intermediateRate, ONE_SHARE);
            uint256 managementFeesOwed = rawAUM - postManagementFeeAUM;

            // Initialize performance fees and set initial new rate
            uint256 performanceFeesOwed = 0;
            newExchangeRate = uint96(intermediateRate);

            // Check if intermediate rate exceeds high water mark
            // If so, calculate performance fees and update new rate
            // Performance fees are calculated as difference between post management fee AUM
            // and post performance fee AUM
            // postPerformanceFeeAUM = postManagementFeeAUM - performanceFeesOwed
            if (intermediateRate > state.highestExchangeRate && state.performanceFee > 0) {
                // cache old high water mark
                uint256 oldHighWaterMark = state.highestExchangeRate;

                // Update new high water mark
                state.highestExchangeRate = intermediateRate;

                // newExchangeRate = intermediateRate * (1 - pf) + oldHighWaterMark * pf
                // where pf is the performance fee as a ratio
                newExchangeRate = uint96(
                    intermediateRate.mulDivDown(uint256(1e4 - state.performanceFee), 1e4).add(
                        oldHighWaterMark.mulDivDown(state.performanceFee, 1e4)
                    )
                );

                // Calculate performance fees as AUM difference
                uint256 postAllFeesAUM = shareSupplyToUse.mulDivDown(newExchangeRate, ONE_SHARE);
                performanceFeesOwed = postManagementFeeAUM - postAllFeesAUM;
            }
            // update state and emit events
            state.exchangeRate = newExchangeRate;
            state.totalSharesLastUpdate = uint128(currentTotalShares);
            state.lastUpdateTimestamp = currentTime;
            state.feesOwedInBase += uint128(managementFeesOwed + performanceFeesOwed);

            emit FeesCalculated(managementFeesOwed, performanceFeesOwed);
            emit ExchangeRateUpdated(uint96(currentExchangeRate), newExchangeRate, currentTime);
        }
    }

    /**
     * @notice Claim pending fees.
     * @dev This function must be called by the BoringVault.
     * @dev This function will lose precision if the exchange rate
     *      decimals is greater than the feeAsset's decimals.
     * @dev to avoid intermediary rounding errors the following function is used to calculate the rate with decimal
     * changes:
     * F = feesOwedInFeeAsset
     * D_f = feeAssetDecimals
     * D_b = decimals
     * R = rate
     *
     * D_f > D_b:
     *  feesOwedInFeeAsset = F * 10^( 2 * D_f ) / ( 10^D_b * R )
     *
     * The function is derived from the formula: F * 10^( D_f - D_b ) * 10^D_f / R
     * This was the previous implementation that stored the feesOwedInBase in the decimal adjusted version (10^( D_f -
     * D_b )) before dividing by rate
     * The above formula is fundamentally the same but includes the decimal conversion to avoid rounding errors
     * compounding in an intermediate step
     */
    function claimFees(ERC20 feeAsset) external {
        if (msg.sender != address(vault)) revert AccountantWithRateProviders__OnlyCallableByBoringVault();

        AccountantState storage state = accountantState;
        if (state.isPaused) revert AccountantWithRateProviders__Paused();
        if (state.feesOwedInBase == 0) revert AccountantWithRateProviders__ZeroFeesOwed();

        // Determine amount of fees owed in feeAsset.
        uint256 feesOwedInFeeAsset;
        RateProviderData memory data = rateProviderData[feeAsset];

        // if fee asset is the base asset avoid the calculation
        if (address(feeAsset) == address(base)) {
            feesOwedInFeeAsset = state.feesOwedInBase;
        } else {
            uint8 feeAssetDecimals = ERC20(feeAsset).decimals();
            // if the free asset is pegged to base then just set the rate to 1 in the decimals of the fee asset
            uint256 rate = (data.isPeggedToBase) ? 10 ** feeAssetDecimals : data.rateProvider.getRate();

            // calculate the fees owed in fee asset
            feesOwedInFeeAsset = (state.feesOwedInBase * 10 ** (feeAssetDecimals * 2)) / ((10 ** decimals) * rate);
        }

        // Zero out fees owed.
        state.feesOwedInBase = 0;
        // Transfer fee asset to payout address.
        feeAsset.safeTransferFrom(msg.sender, state.payoutAddress, feesOwedInFeeAsset);

        emit FeesClaimed(address(feeAsset), feesOwedInFeeAsset);
    }

    // ========================================= RATE FUNCTIONS =========================================

    /**
     * @notice Get this BoringVault's current rate in the base.
     */
    function getRate() public view returns (uint256 rate) {
        rate = accountantState.exchangeRate;
    }

    /**
     * @notice Get this BoringVault's current rate in the base.
     * @dev Revert if paused.
     */
    function getRateSafe() external view returns (uint256 rate) {
        if (accountantState.isPaused) revert AccountantWithRateProviders__Paused();
        rate = getRate();
    }

    /**
     * @notice Get this BoringVault's current rate in the provided quote.
     * @dev `quote` must have its RateProviderData set, else this will revert.
     * @dev This function will lose precision if the exchange rate
     *      decimals is greater than the quote's decimals.
     */
    function getRateInQuote(ERC20 quote) public view returns (uint256 rateInQuote) {
        if (address(quote) == address(base)) {
            rateInQuote = accountantState.exchangeRate;
        } else {
            RateProviderData memory data = rateProviderData[quote];
            uint8 quoteDecimals = ERC20(quote).decimals();
            uint256 exchangeRateInQuoteDecimals = changeDecimals(accountantState.exchangeRate, decimals, quoteDecimals);
            if (data.isPeggedToBase) {
                rateInQuote = exchangeRateInQuoteDecimals;
            } else {
                uint256 quoteRate = data.rateProvider.getRate();
                uint256 oneQuote = 10 ** quoteDecimals;
                rateInQuote = oneQuote.mulDivDown(exchangeRateInQuoteDecimals, quoteRate);
            }
        }
    }

    /**
     * @notice Get this BoringVault's current rate in the provided quote.
     * @dev `quote` must have its RateProviderData set, else this will revert.
     * @dev Revert if paused.
     */
    function getRateInQuoteSafe(ERC20 quote) external view returns (uint256 rateInQuote) {
        if (accountantState.isPaused) revert AccountantWithRateProviders__Paused();
        rateInQuote = getRateInQuote(quote);
    }

    // ========================================= INTERNAL HELPER FUNCTIONS =========================================
    /**
     * @notice Used to change the decimals of precision used for an amount.
     */
    function changeDecimals(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals < toDecimals) {
            return amount * 10 ** (toDecimals - fromDecimals);
        } else {
            return amount / 10 ** (fromDecimals - toDecimals);
        }
    }
}
