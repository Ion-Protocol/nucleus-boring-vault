// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { AuthOwnable2Step, Authority } from "src/helper/AuthOwnable2Step.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title AccountantWithRateProviders
 * @custom:security-contact security@molecularlabs.io
 */
contract AccountantWithRateProviders is AuthOwnable2Step, IRateProvider {
    using Math for uint256;
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
     * @param functionCalldata to call the rateProvider in order to get the rate
     */
    struct RateProviderData {
        bool isPeggedToBase;
        address rateProvider;
        bytes functionCalldata;
    }

    // ========================================= STATE =========================================

    /**
     * @notice Store the accountant state in 3 packed slots.
     */
    AccountantState public accountantState;

    /**
     * @notice Maps ERC20s to their RateProviderData.
     */
    mapping(ERC20 => RateProviderData[]) public rateProviderData;

    //============================== ERRORS ===============================

    error AccountantWithRateProviders__UpperBoundTooSmall();
    error AccountantWithRateProviders__LowerBoundTooLarge();
    error AccountantWithRateProviders__ManagementFeeTooLarge();
    error AccountantWithRateProviders__PerformanceFeeTooLarge();
    error AccountantWithRateProviders__Paused();
    error AccountantWithRateProviders__ZeroFeesOwed();
    error AccountantWithRateProviders__OnlyCallableByBoringVault();
    error AccountantWithRateProviders__UpdateDelayTooLarge();
    error AccountantWithRateProviders__RateProviderCallFailed(address rateProvider);
    error AccountantWithRateProviders__ExchangeRateAlreadyHighest();
    error AccountantWithRateProviders__RateProviderDataEmpty();
    error AccountantWithRateProviders__InvalidRateReturned();
    error AccountantWithRateProviders__ZeroRate();
    error AccountantWithRateProviders__ZeroQuoteRate();
    error AccountantWithRateProviders__VaultBaseDecimalMismatch();

    //============================== EVENTS ===============================

    event Paused();
    event Unpaused();
    event DelayInSecondsUpdated(uint32 oldDelay, uint32 newDelay);
    event UpperBoundUpdated(uint16 oldBound, uint16 newBound);
    event LowerBoundUpdated(uint16 oldBound, uint16 newBound);
    event ManagementFeeUpdated(uint16 oldFee, uint16 newFee);
    event PerformanceFeeUpdated(uint16 oldFee, uint16 newFee);
    event PayoutAddressUpdated(address oldPayout, address newPayout);
    event RateProviderDataUpdated(address indexed asset, RateProviderData[] newRateProviderData);
    event ExchangeRateUpdated(uint96 oldRate, uint96 newRate, uint64 currentTime);
    event PerformanceFeesAccrued(uint256 performanceFees);
    event ManagementFeesAccrued(uint256 managementFees);
    event FeesClaimed(address indexed feeAsset, uint256 amount);
    event HighestExchangeRateReset();

    //============================== CONSTANTS ===============================
    uint8 constant MIN_RATE_DECIMALS_DEVIATION = 1; // ie 10 ** (18 - 1) is the minimum accepted rate from a rate
        // provider with 18 decimals
    uint8 constant MAX_RATE_DECIMALS_DEVIATION = 1; // ie 10 ** (18 + 1) is the maximum accepted rate from a rate
        // provider with 18 decimals

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
        AuthOwnable2Step(_owner, Authority(address(0)))
    {
        base = ERC20(_base);
        decimals = ERC20(_base).decimals();
        vault = BoringVault(payable(_vault));

        if (decimals != vault.decimals()) {
            revert AccountantWithRateProviders__VaultBaseDecimalMismatch();
        }

        ONE_SHARE = 10 ** decimals;
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
     * @notice Pause this contract, which prevents future calls to `updateExchangeRate`
     * @dev Callable by MULTISIG_ROLE.
     */
    function pause() external requiresAuth {
        accountantState.isPaused = true;
        emit Paused();
    }

    /**
     * @notice Unpause this contract, which allows future calls to `updateExchangeRate`
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
        emit PerformanceFeeUpdated(oldFee, performanceFee);
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
     * @dev Setting rate provider data will clear existing data for this asset
     */
    function setRateProviderData(ERC20 asset, RateProviderData[] calldata _rateProviderData) external requiresAuth {
        // Clear existing data
        delete rateProviderData[asset];

        for (uint256 i; i < _rateProviderData.length; ++i) {
            rateProviderData[asset].push(_rateProviderData[i]);
        }
        emit RateProviderDataUpdated(address(asset), _rateProviderData);
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
    function updateExchangeRate(uint96 newExchangeRate) external requiresAuth {
        AccountantState storage state = accountantState;

        if (state.isPaused) revert AccountantWithRateProviders__Paused();
        uint64 currentTime = uint64(block.timestamp);
        uint256 currentExchangeRate = state.exchangeRate;
        uint256 currentTotalShares = vault.totalSupply();
        if (
            currentTime < state.lastUpdateTimestamp + state.minimumUpdateDelayInSeconds
                || newExchangeRate > currentExchangeRate.mulDiv(state.allowedExchangeRateChangeUpper, 1e4)
                || newExchangeRate < currentExchangeRate.mulDiv(state.allowedExchangeRateChangeLower, 1e4)
        ) {
            // Instead of reverting, pause the contract. This way the exchange rate updater is able to update the
            // exchange rate
            // to a better value, and pause it.
            state.isPaused = true;
            emit Paused();
            return;
        } else {
            // Only update fees if we are not paused.
            // Update fee accounting.
            uint256 shareSupplyToUse =
                state.totalSharesLastUpdate < currentTotalShares ? state.totalSharesLastUpdate : currentTotalShares;
            // Use the minimum between current total supply and total supply for last update.

            // Determine management fees owned.
            uint256 timeDelta;
            // time delta should always be positive as block.timestamp is the only source for this value
            unchecked {
                timeDelta = currentTime - state.lastUpdateTimestamp;
            }
            uint256 minimumAssets = newExchangeRate > currentExchangeRate
                ? shareSupplyToUse.mulDiv(currentExchangeRate, ONE_SHARE)
                : shareSupplyToUse.mulDiv(newExchangeRate, ONE_SHARE);
            uint256 managementFeesAnnual = minimumAssets.mulDiv(state.managementFee, 1e4);
            uint256 newFeesOwedInBase = managementFeesAnnual.mulDiv(timeDelta, 365 days);
            emit ManagementFeesAccrued(managementFeesAnnual);

            if (newExchangeRate > state.highestExchangeRate) {
                unchecked {
                    if (state.performanceFee > 0) {
                        uint256 changeInAssets =
                            uint256(newExchangeRate - state.highestExchangeRate).mulDiv(shareSupplyToUse, ONE_SHARE);
                        uint256 performanceFees = changeInAssets.mulDiv(state.performanceFee, 1e4);
                        newFeesOwedInBase += performanceFees;
                        emit PerformanceFeesAccrued(performanceFees);
                    }
                }
                state.highestExchangeRate = newExchangeRate;
            }

            unchecked {
                state.feesOwedInBase += uint128(newFeesOwedInBase);
            }
        }

        state.exchangeRate = newExchangeRate;
        state.totalSharesLastUpdate = uint128(currentTotalShares);
        state.lastUpdateTimestamp = currentTime;

        emit ExchangeRateUpdated(uint96(currentExchangeRate), newExchangeRate, currentTime);
    }

    /**
     * @notice Claim pending fees.
     * @dev This function must be called by the BoringVault.
     * @dev This function will lose precision if the exchange rate
     *      decimals is greater than the feeAsset's decimals.
     * @dev to avoid intermediary rounding errors the following function is used to calculate the rate with decimal
     * changes:
     * F = feesOwedInBaseAsset
     * D_f = feeAssetDecimals
     * D_b = decimals
     * R = rate
     *
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

        // if fee asset is the base asset avoid the calculation
        if (address(feeAsset) == address(base)) {
            feesOwedInFeeAsset = state.feesOwedInBase;
        } else {
            uint8 feeAssetDecimals = feeAsset.decimals();
            // use the max rate for fees
            uint256 rate = getMaxRate(feeAsset);
            if (rate == 0) revert AccountantWithRateProviders__ZeroRate();

            // calculate the fees owed in fee asset
            uint256 _feesOwedInFeeAsset =
                uint256(state.feesOwedInBase).mulDiv(10 ** (feeAssetDecimals * 2), (10 ** decimals) * rate);
            assert(_feesOwedInFeeAsset < 2 ** 128);

            feesOwedInFeeAsset = uint128(_feesOwedInFeeAsset);
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
     * @notice helper function to return the shares out for 1 deposit asset
     */
    function getDepositRate(ERC20 depositAsset) external view returns (uint256 rate) {
        rate = getSharesForDepositAmount(depositAsset, 10 ** depositAsset.decimals());
    }

    /**
     * @notice Return the shares output for a given deposit amount of a token
     * @dev Math is used to compute this value among assets with varying decimals with minimal rounding errors
     * Key:
     *   - Q: Quote asset decimals
     *   - B: Base asset decimals
     *   - x: depositAmount provided in quote decimals
     *   - e: exchangeRate of the accountant returned in base decimals
     *   - q: QuoteRate returned by the asset rate provider returned in quote decimals. If asset is pegged short circuit
     * and set this as 10^Q
     *
     * The math is based on the old way of computing this value where shares is the deposit amount multiplied by a rate
     * computed from quote and exchange rates
     * shares = x * 10^B / RIQ()
     * RIQ (rate in quote) = 10**Q * e * 10^(Q-B) / q
     *
     * However, the above function had a tendency to produce rounding errors. As truncation and division was done in
     * intermediate steps.
     * To make it more accurate we have derived the following formula:
     * shares = x * q * 10^(2*B) / (e * 10**(2*Q))
     *
     * @param depositAsset the asset being deposited
     * @param depositAmount the amount of the asset being deposited
     * @return shares the amount of shares returned for the given deposit amount
     */
    function getSharesForDepositAmount(
        ERC20 depositAsset,
        uint256 depositAmount
    )
        public
        view
        returns (uint256 shares)
    {
        uint256 Q = depositAsset.decimals();
        uint256 B = decimals;
        uint256 e = accountantState.exchangeRate;
        uint256 q = getMinRate(depositAsset);

        if (q == 0) revert AccountantWithRateProviders__ZeroRate();

        shares = depositAmount.mulDiv(q * 10 ** (2 * B), e * 10 ** (2 * Q));
    }

    /**
     * @notice Return the asset output for a given amount of shares redeemed for withdraw
     * @dev Math is used to compute this value among assets with varying decimals with minimal rounding errors
     * Key:
     *   - Q: Quote asset decimals
     *   - B: Base asset decimals
     *   - S: shareAmount provided in base decimals
     *   - e: exchangeRate of the accountant returned in base decimals
     *   - q: QuoteRate returned by the asset rate provider returned in quote decimals. If asset is pegged short circuit
     * and set this as 10^Q
     *
     * The math is based on the old way of computing this value where assets is the deposit amount multiplied by a rate
     * computed from quote and exchange rates
     * assets = S* RIQ() / 10^B
     * RIQ (rate in quote) = 10**Q * e * 10^(Q-B) / q
     *
     * However, the above function had a tendency to produce rounding errors. As truncation and division was done in
     * intermediate steps.
     * To make it more accurate we have derived the following formula:
     * assets = S * e * 10^(2*Q) / (q * 10**(2*B))
     *
     * @param withdrawAsset the asset being withdrawn
     * @param shareAmount the amount of shares being withdrawn
     * @return assetsOut the amount of assets out for the given share amount
     */
    function getAssetsOutForShares(ERC20 withdrawAsset, uint256 shareAmount) public view returns (uint256 assetsOut) {
        uint256 Q = withdrawAsset.decimals();
        uint256 B = decimals;
        uint256 e = accountantState.exchangeRate;
        uint256 q = getMaxRate(withdrawAsset);

        if (q == 0) revert AccountantWithRateProviders__ZeroQuoteRate();

        assetsOut = shareAmount.mulDiv(e * 10 ** (2 * Q), q * 10 ** (2 * B));
    }

    /**
     * @notice helper function to return the assets out for 1 share
     * @param withdrawAsset the asset to get the withdraw rate for
     * @return rate the assets out for 1 share withdrawn
     */
    function getWithdrawRate(ERC20 withdrawAsset) external view returns (uint256 rate) {
        rate = getAssetsOutForShares(withdrawAsset, ONE_SHARE);
    }

    /**
     * @notice helper function to return the rate for a given asset using a particular rate provider by index
     * @param asset the asset to get the rate for
     * @param index the index of the rate provider to use
     * @return rate the rate for the asset using the given rate provider
     */
    function getRateForAsset(ERC20 asset, uint256 index) public view returns (uint256 rate) {
        RateProviderData[] memory data = rateProviderData[asset];
        uint8 assetDecimals = asset.decimals();
        rate = data[index].isPeggedToBase ? 10 ** assetDecimals : _getRateFromRateProvider(data[index], assetDecimals);
    }

    /**
     * @notice helper function to return the max rate for a given asset among all rate providers
     * @param asset the asset to get the max rate for
     * @return maxRate the max rate for the asset
     */
    function getMaxRate(ERC20 asset) public view returns (uint256 maxRate) {
        RateProviderData[] memory data = rateProviderData[asset];
        uint8 assetDecimals = asset.decimals();

        if (asset == base) {
            return 10 ** decimals;
        }

        if (data.length == 0) {
            revert AccountantWithRateProviders__RateProviderDataEmpty();
        }

        for (uint256 i; i < data.length; ++i) {
            uint256 rate =
                data[i].isPeggedToBase ? 10 ** assetDecimals : _getRateFromRateProvider(data[i], assetDecimals);
            if (rate > maxRate) {
                maxRate = rate;
            }
        }
    }

    /**
     * @notice helper function to return the min rate for a given asset among all rate providers
     * @param asset the asset to get the min rate for
     * @return minRate the min rate for the asset
     */
    function getMinRate(ERC20 asset) public view returns (uint256 minRate) {
        RateProviderData[] memory data = rateProviderData[asset];
        minRate = type(uint256).max;
        uint8 assetDecimals = asset.decimals();

        if (asset == base) {
            return 10 ** decimals;
        }

        if (data.length == 0) {
            revert AccountantWithRateProviders__RateProviderDataEmpty();
        }

        minRate = data[0].isPeggedToBase ? 10 ** assetDecimals : _getRateFromRateProvider(data[0], assetDecimals);

        if (data.length == 1) {
            return minRate;
        }

        for (uint256 i = 1; i < data.length; ++i) {
            uint256 rate =
                data[i].isPeggedToBase ? 10 ** assetDecimals : _getRateFromRateProvider(data[i], assetDecimals);
            if (rate < minRate) {
                minRate = rate;
            }
        }
    }

    // ========================================= INTERNAL HELPER FUNCTIONS =========================================

    /**
     * @notice helper function to check if the rate is within the accepted bounds
     * @dev if the rate is not within the accepted bounds, revert, this is to prevent any mistakes regarding rate
     * incorrectly provided rate providers or their return types being mismatched
     * @param rate the rate to check
     * @param assetDecimals the decimals of the asset
     */
    function _checkRate(uint256 rate, uint8 assetDecimals) internal pure {
        if (
            assetDecimals < MIN_RATE_DECIMALS_DEVIATION || rate < 10 ** (assetDecimals - MIN_RATE_DECIMALS_DEVIATION)
                || rate > 10 ** (assetDecimals + MIN_RATE_DECIMALS_DEVIATION)
        ) {
            revert AccountantWithRateProviders__InvalidRateReturned();
        }
    }

    /**
     * @notice helper function to get the rate from a rate provider
     * @param data the rate provider data
     * @param assetDecimals the decimals of the asset
     * @return rate the rate from the rate provider
     */
    function _getRateFromRateProvider(
        RateProviderData memory data,
        uint8 assetDecimals
    )
        internal
        view
        returns (uint256 rate)
    {
        (bool success, bytes memory returnBytes) = data.rateProvider.staticcall(data.functionCalldata);
        if (!success) {
            revert AccountantWithRateProviders__RateProviderCallFailed(data.rateProvider);
        }
        rate = abi.decode(returnBytes, (uint256));
        _checkRate(rate, assetDecimals);
    }
}
