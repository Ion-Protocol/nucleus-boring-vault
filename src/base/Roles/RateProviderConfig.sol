// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Auth, Authority } from "solmate/auth/Auth.sol";

contract RateProviderConfig is Auth {
    struct RateProviderData {
        bool isPeggedToBase;
        address rateProvider;
        bytes functionCalldata;
        uint256 minRate;
        uint256 maxRate;
    }

    error RateProvider__RateProviderCallFailed(address rateProvider);
    error RateProvider__RateProviderDataEmpty();
    error RateProvider__ZeroRate();
    error RateProvider__RateTooLow(address rateProvider, uint256 minRate, uint256 actualRate);
    error RateProvider__RateTooHigh(address rateProvider, uint256 maxRate, uint256 actualRate);

    // base asset => quote asset => RateProviderData[]
    mapping(ERC20 => mapping(ERC20 => RateProviderData[])) public rateProviderData;

    event RateProviderDataUpdated(address indexed base, address indexed quote, RateProviderData[] newRateProviderData);

    constructor(address _owner) Auth(_owner, Authority(address(0))) { }

    function setRateProviderData(
        ERC20 base,
        ERC20 quote,
        RateProviderData[] calldata _rateProviderData
    )
        external
        requiresAuth
    {
        // Clear existing data
        delete rateProviderData[base][quote];

        // Set new data
        for (uint256 i; i < _rateProviderData.length; ++i) {
            rateProviderData[base][quote].push(_rateProviderData[i]);
        }

        emit RateProviderDataUpdated(address(base), address(quote), _rateProviderData);
    }

    function getMaxRate(ERC20 base, ERC20 quote) public view returns (uint256 maxRate) {
        RateProviderData[] memory data = rateProviderData[base][quote];
        uint8 quoteDecimals = quote.decimals();

        if (base == quote) {
            return 10 ** quoteDecimals;
        }

        if (data.length == 0) {
            revert RateProvider__RateProviderDataEmpty();
        }

        for (uint256 i; i < data.length; ++i) {
            uint256 rate = data[i].isPeggedToBase ? 10 ** quoteDecimals : _getRateFromRateProvider(data[i]);
            if (rate > maxRate) {
                maxRate = rate;
            }
        }
    }

    function getMinRate(ERC20 base, ERC20 quote) public view returns (uint256 minRate) {
        RateProviderData[] memory data = rateProviderData[base][quote];
        minRate = type(uint256).max;
        uint8 quoteDecimals = quote.decimals();

        if (base == quote) {
            return 10 ** quoteDecimals;
        }

        if (data.length == 0) {
            revert RateProvider__RateProviderDataEmpty();
        }

        for (uint256 i; i < data.length; ++i) {
            uint256 rate = data[i].isPeggedToBase ? 10 ** quoteDecimals : _getRateFromRateProvider(data[i]);
            if (rate < minRate) {
                minRate = rate;
            }
        }
    }

    /**
     * @notice helper function to return the rate for a given asset using a particular rate provider by index
     * @param base the base asset
     * @param quote the quote asset
     * @param index the index of the rate provider to use
     * @return rate the rate for the asset using the given rate provider
     */
    function getRateForAssetWithIndex(ERC20 base, ERC20 quote, uint256 index) public view returns (uint256 rate) {
        RateProviderData[] memory data = rateProviderData[base][quote];
        uint8 quoteDecimals = quote.decimals();
        rate = data[index].isPeggedToBase ? 10 ** quoteDecimals : _getRateFromRateProvider(data[index]);
    }

    function _getRateFromRateProvider(RateProviderData memory data) internal view returns (uint256 rate) {
        (bool success, bytes memory returnBytes) = data.rateProvider.staticcall(data.functionCalldata);
        if (!success) {
            revert RateProvider__RateProviderCallFailed(data.rateProvider);
        }
        rate = abi.decode(returnBytes, (uint256));

        if (rate == 0) {
            revert RateProvider__ZeroRate();
        }

        // Add bounds checking
        if (rate < data.minRate) {
            revert RateProvider__RateTooLow(data.rateProvider, data.minRate, rate);
        }
        if (rate > data.maxRate) {
            revert RateProvider__RateTooHigh(data.rateProvider, data.maxRate, rate);
        }
    }
}
