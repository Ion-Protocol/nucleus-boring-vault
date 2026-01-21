// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { SlvlUSDRateProvider } from "src/oracles/SlvlUSDRateProvider.sol";
import { LvlUSDRateProvider } from "src/oracles/LvlUSDRateProvider.sol";
import { Test } from "@forge-std/Test.sol";

interface AggregatorV3Interface {

    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
    function latestAnswer() external view returns (int256);

}

abstract contract RateProviderSimpleTest is Test {

    IRateProvider internal rateProvider;

    uint256 internal expectedMinPrice;
    uint256 internal expectedMaxPrice;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 22_498_822);
    }

    function test_GetRateExpectedPrice() public virtual {
        uint256 rate = rateProvider.getRate();

        assertGe(rate, expectedMinPrice, "min price");
        assertLe(rate, expectedMaxPrice, "max price");
    }

}

contract LvlUSDRateProviderTest is RateProviderSimpleTest {

    function setUp() public override {
        super.setUp();

        rateProvider = IRateProvider(address(new LvlUSDRateProvider()));

        expectedMinPrice = 1e18;
        expectedMaxPrice = 1.1e18;
    }

    function test_GetRateExpectedPrice() public override {
        AggregatorV3Interface USD_PER_USDC_CL = AggregatorV3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
        uint256 usdPerUsdc = uint256(USD_PER_USDC_CL.latestAnswer());

        uint256 rate = rateProvider.getRate(); // should always be 18 decimals

        if (usdPerUsdc > 1e8) {
            uint256 usdcPerUsd = 1e6 * 1e8 / usdPerUsdc;
            assertEq(rate, usdcPerUsd * 10 ** 12, "if USDC is over peg, rate is inverse of USDC price in USD");
        } else if (usdPerUsdc <= 1e8) {
            assertEq(rate, 1e18, "if USDC is equal to or under peg, rate must be 1");
        }
    }

}

contract SlvlUSDRateProviderTest is RateProviderSimpleTest {

    function setUp() public override {
        super.setUp();

        rateProvider = IRateProvider(address(new SlvlUSDRateProvider()));

        expectedMinPrice = 1e18;
        expectedMaxPrice = 1.1e18;
    }

}
