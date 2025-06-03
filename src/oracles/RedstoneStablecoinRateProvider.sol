// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IRateProvider } from "./../interfaces/IRateProvider.sol";
import { IPriceFeed } from "./../interfaces/IPriceFeed.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @notice Reports the price of a token in terms of an underlying stablecoin. The underlying price
 * feed must be compatible with the Redstone interface.
 *
 * Requires 2 oracles:
 *  - USDFeed-> Returns price of the chosen stablecoin in USD
 *  - TargetFeed-> Returns the price of the target asset in USD
 *  Ex. USDT -> USDC would require a USDT/USD TargetFeed and a USDC/USD USDFeed
 * @custom:security-contact security@molecularlabs.io
 */
contract RedstoneStablecoinRateProvider is IRateProvider {
    using SafeCast for int256;

    error MaxTimeFromLastUpdatePassed(uint256 blockTimestamp, uint256 lastUpdated);
    error InvalidPriceFeedDecimals(uint8 priceFeedDecimals);
    error InvalidDescription();

    /**
     * @notice The asset pairs the rate provider queries.
     */
    string public DESCRIPTION_USDFeed;
    string public DESCRIPTION_TargetFeed;

    /**
     * @notice The underlying price feeds that this rate provider reads from.
     */
    IPriceFeed public immutable PRICE_FEED_USDFeed;
    IPriceFeed public immutable PRICE_FEED_TargetFeed;

    /**
     * @notice Number of seconds since last update to determine whether the
     * price feeds are stale.
     */
    uint256 public immutable MAX_TIME_FROM_LAST_UPDATE;

    /**
     * @notice The preicision of the rate returned by this contract.
     */
    uint8 public immutable RATE_DECIMALS;

    /**
     * @notice The offset between the intended return decimals and the price
     * feed decimals.
     * @dev Based on the `PriceFeedType`, the price feed's asset pair label is
     * retrieved differently.
     */
    uint8 public immutable DECIMALS_OFFSET;

    /// @notice all redstone oracles should have 8 decimals
    uint8 public constant REDSTONE_DECIMALS = 8;

    /**
     * @param _descriptionUSDFeed The usdFeed asset pair. ex USDC/USD
     * @param _descriptionTargetFeed The targetFeed asset pair. ex USDT/USD
     */
    constructor(
        string memory _descriptionUSDFeed,
        string memory _descriptionTargetFeed,
        IPriceFeed _usdFeed,
        IPriceFeed _targetFeed,
        uint256 _maxTimeFromLastUpdate,
        uint8 _rateDecimals
    ) {
        if (!_isEqual(_descriptionUSDFeed, _usdFeed.description())) revert InvalidDescription();
        if (!_isEqual(_descriptionTargetFeed, _targetFeed.description())) revert InvalidDescription();

        uint8 _priceFeedDecimals = _usdFeed.decimals();
        if (_priceFeedDecimals != REDSTONE_DECIMALS) {
            revert InvalidPriceFeedDecimals(_priceFeedDecimals);
        }
        _priceFeedDecimals = _targetFeed.decimals();

        if (_priceFeedDecimals != REDSTONE_DECIMALS) {
            revert InvalidPriceFeedDecimals(_priceFeedDecimals);
        }

        unchecked {
            DECIMALS_OFFSET = REDSTONE_DECIMALS - _rateDecimals;
        }

        DESCRIPTION_USDFeed = _descriptionUSDFeed;
        DESCRIPTION_TargetFeed = _descriptionTargetFeed;
        PRICE_FEED_USDFeed = _usdFeed;
        PRICE_FEED_TargetFeed = _targetFeed;
        MAX_TIME_FROM_LAST_UPDATE = _maxTimeFromLastUpdate;
        RATE_DECIMALS = _rateDecimals;
    }

    /**
     * @notice Gets the price of the target token in terms of the usd feed stablecoin.
     * @return rate in terms of usd feed stablecoin.
     */
    function getRate() public view returns (uint256 rate) {
        _validityCheck();

        (, int256 _usdRate,, uint256 lastUpdatedAtUsd,) = PRICE_FEED_USDFeed.latestRoundData();

        if (block.timestamp - lastUpdatedAtUsd > MAX_TIME_FROM_LAST_UPDATE) {
            revert MaxTimeFromLastUpdatePassed(block.timestamp, lastUpdatedAtUsd);
        }

        (, int256 _targetRate,, uint256 lastUpdatedAtTarget,) = PRICE_FEED_TargetFeed.latestRoundData();

        if (block.timestamp - lastUpdatedAtTarget > MAX_TIME_FROM_LAST_UPDATE) {
            revert MaxTimeFromLastUpdatePassed(block.timestamp, lastUpdatedAtTarget);
        }

        rate = (_targetRate.toUint256() * _usdRate.toUint256()) / 10 ** (REDSTONE_DECIMALS + DECIMALS_OFFSET);
    }

    /**
     * @dev To revert upon custom checks such as sequencer liveness.
     */
    // solhint-disable-next-line no-empty-blocks
    function _validityCheck() internal view virtual { }

    function _isEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _isEqual(string memory a, bytes32 b) internal pure returns (bool) {
        return bytes32(bytes(a)) == b;
    }
}
