// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { MonotonicExchangeRateOracle } from "src/oracles/MonotonicExchangeRateOracle.sol";

contract MonotonicExchangeRateOracleTest is Test, MainnetAddresses {
    AccountantWithRateProviders public accountantWeth;
    AccountantWithRateProviders public accountantUsdc;

    function setUp() external {
        string memory rpcKey = "MAINNET_RPC_URL";
        _startFork(rpcKey);
        accountantWeth = new AccountantWithRateProviders(
            address(this), address(WETH), address(this), 1e18, address(WETH), 2.5e4, 0.5e4, 0, 0
        );
        accountantUsdc = new AccountantWithRateProviders(
            address(this), address(USDC), address(this), 1e6, address(USDC), 2.5e4, 0.5e4, 0, 0
        );
    }

    function testAccountantWeth() external {
        MonotonicExchangeRateOracle oracle = new MonotonicExchangeRateOracle(address(this), accountantWeth);
        assertEq(oracle.getRate(), 1e18, "starting rate should be 1e18");

        accountantWeth.updateExchangeRate(1.2e18);
        assertEq(oracle.getRate(), 1.2e18, "next rate should be 1.2e18");

        accountantWeth.updateExchangeRate(1.1e18);
        assertEq(oracle.getRate(), 1.2e18, "next rate should still be 1.2e18");

        oracle.setHighwaterMark(1.9e18);
        assertEq(oracle.getRate(), 1.9e18, "rate should manually be set to 1.9e18");
    }

    function testAccountantUsdc() external {
        MonotonicExchangeRateOracle oracle = new MonotonicExchangeRateOracle(address(this), accountantUsdc);
        assertEq(oracle.getRate(), 1e18, "starting rate should be 1e18");

        accountantUsdc.updateExchangeRate(1.2e6);
        assertEq(oracle.getRate(), 1.2e18, "next rate should be 1.2e18");

        accountantUsdc.updateExchangeRate(1.1e6);
        assertEq(oracle.getRate(), 1.2e18, "next rate should still be 1.2e18");

        oracle.setHighwaterMark(1.9e6);
        assertEq(oracle.getRate(), 1.9e18, "rate should manually be set to 1.9e18");
    }

    function _startFork(string memory rpcKey) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey));
        vm.selectFork(forkId);
    }
}
