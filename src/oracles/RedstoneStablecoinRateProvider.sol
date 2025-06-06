// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IRateProvider } from "./../interfaces/IRateProvider.sol";
import { IPriceFeed } from "./../interfaces/IPriceFeed.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

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
contract RedstoneStablecoinRateProvider is Auth, IRateProvider {
    using SafeCast for int256;

    error MaxTimeFromLastUpdatePassed(uint256 blockTimestamp, uint256 lastUpdated);
    error InvalidPriceFeedDecimals(uint8 priceFeedDecimals);
    error InvalidDescription();
    error BoundsViolated(uint256 rate, uint256 violatedBound);

    /**
     * @notice The asset pairs the rate provider queries.
     */
    string public DESCRIPTION_USDFeed;
    string public DESCRIPTION_TargetFeed;

    /**
     * @notice bounds on rate to keep it at a reasonable level
     */
    uint256 public lowerBound;

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

    /// @notice all redstone oracles should have 8 decimals
    uint8 public constant REDSTONE_DECIMALS = 8;

    /**
     * @param _descriptionUSDFeed The usdFeed asset pair. ex USDC/USD
     * @param _descriptionTargetFeed The targetFeed asset pair. ex USDT/USD
     */
    constructor(
        address _owner,
        string memory _descriptionUSDFeed,
        string memory _descriptionTargetFeed,
        ERC20 _targetAsset,
        IPriceFeed _usdFeed,
        IPriceFeed _targetFeed,
        uint256 _maxTimeFromLastUpdate
    )
        Auth(_owner, Authority(address(0)))
    {
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

        RATE_DECIMALS = _targetAsset.decimals();

        DESCRIPTION_USDFeed = _descriptionUSDFeed;
        DESCRIPTION_TargetFeed = _descriptionTargetFeed;
        PRICE_FEED_USDFeed = _usdFeed;
        PRICE_FEED_TargetFeed = _targetFeed;
        MAX_TIME_FROM_LAST_UPDATE = _maxTimeFromLastUpdate;
        // Default Lower Bound is 5 bps
        lowerBound = 10 ** RATE_DECIMALS * 9995 / 10_000;
    }

    /**
     * @notice change the bounds (defaults are 5 bps based on decimals provided)
     * @dev callable by OWNER
     */
    function setLowerBound(uint256 _lowerBound) external requiresAuth {
        lowerBound = _lowerBound;
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

        // rate(target decimals) = targetRate(8) * 10^(target decimals) / usdRate(8)
        rate = (_targetRate.toUint256() * 10 ** (RATE_DECIMALS) / _usdRate.toUint256());

        _rateCheck(rate);

        uint256 ONE = 10 ** RATE_DECIMALS;

        if (rate > ONE) {
            return ONE;
        }
    }

    /**
     * @dev To revert upon custom checks such as sequencer liveness.
     */
    // solhint-disable-next-line no-empty-blocks
    function _validityCheck() internal view virtual { }

    /**
     * @dev To check rate remains in reasonable bounds
     */
    function _rateCheck(uint256 rate) internal view {
        if (rate < lowerBound) {
            revert BoundsViolated(rate, lowerBound);
        }
    }

    function _isEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _isEqual(string memory a, bytes32 b) internal pure returns (bool) {
        return bytes32(bytes(a)) == b;
    }
}
