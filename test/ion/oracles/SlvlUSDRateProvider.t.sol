// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SlvlUSDRateProvider } from "src/oracles/SlvlUSDRateProvider.sol";
import { Test } from "@forge-std/Test.sol";

contract SlvlUSDRateProviderTest is Test {
    SlvlUSDRateProvider internal rateProvider;

    uint256 internal expectedMinPrice = 1e18;
    uint256 internal expectedMaxPrice = 1.1e18;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        rateProvider = new SlvlUSDRateProvider();
    }

    function test_GetRateExpectedPrice() public view {
        uint256 rate = rateProvider.getRate();

        assertGe(rate, expectedMinPrice, "min price");
        assertLe(rate, expectedMaxPrice, "max price");
    }
}
