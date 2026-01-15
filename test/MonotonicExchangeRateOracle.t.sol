// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { MonotonicExchangeRateOracle } from "src/oracles/MonotonicExchangeRateOracle.sol";
import { OracleRelay } from "src/helper/OracleRelay.sol";

contract MonotonicExchangeRateOracleTest is Test, MainnetAddresses {

    AccountantWithRateProviders public accountantWeth;
    AccountantWithRateProviders public accountantUsdc;

    OracleRelay public oracleRelay;

    function setUp() external {
        string memory rpcKey = "MAINNET_RPC_URL";
        _startFork(rpcKey);
        accountantWeth = new AccountantWithRateProviders(
            address(this), address(WETH), address(this), 1e18, address(WETH), 2.5e4, 0.5e4, 0, 0, 0
        );
        accountantUsdc = new AccountantWithRateProviders(
            address(this), address(USDC), address(this), 1e6, address(USDC), 2.5e4, 0.5e4, 0, 0, 0
        );

        oracleRelay = new OracleRelay(address(this));
    }

    function testAccountantWeth() external {
        MonotonicExchangeRateOracle oracle = new MonotonicExchangeRateOracle(address(this), accountantWeth);
        oracleRelay.setImplementation(address(oracle));
        oracle.update();
        assertEq(oracleRelay.getRate(), 1e18, "starting rate should be 1e18");

        accountantWeth.updateExchangeRate(1.2e18);
        oracle.update();
        assertEq(oracleRelay.getRate(), 1.2e18, "next rate should be 1.2e18");

        accountantWeth.updateExchangeRate(1.1e18);
        oracle.update();
        assertEq(oracleRelay.getRate(), 1.2e18, "next rate should still be 1.2e18");

        oracle.setHighwaterMark(1.9e18);
        assertEq(oracleRelay.getRate(), 1.9e18, "rate should manually be set to 1.9e18");
    }

    function testAccountantUsdc() external {
        MonotonicExchangeRateOracle oracle = new MonotonicExchangeRateOracle(address(this), accountantUsdc);
        oracleRelay.setImplementation(address(oracle));
        oracle.update();
        assertEq(oracleRelay.getRate(), 1e18, "starting rate should be 1e18");

        accountantUsdc.updateExchangeRate(1.2e6);
        oracle.update();
        assertEq(oracleRelay.getRate(), 1.2e18, "next rate should be 1.2e18");

        accountantUsdc.updateExchangeRate(1.1e6);
        oracle.update();
        assertEq(oracleRelay.getRate(), 1.2e18, "next rate should still be 1.2e18");

        oracle.setHighwaterMark(1.9e6);
        assertEq(oracleRelay.getRate(), 1.9e18, "rate should manually be set to 1.9e18");
    }

    function testUpdateImplementation() external {
        MonotonicExchangeRateOracle oracle1 = new MonotonicExchangeRateOracle(address(this), accountantUsdc);
        AccountantWithRateProviders accountantUsdc2 = new AccountantWithRateProviders(
            address(this), address(WETH), address(this), 1e18, address(WETH), 2.5e4, 0.5e4, 0, 0, 0
        );
        MonotonicExchangeRateOracle oracle2 = new MonotonicExchangeRateOracle(address(this), accountantUsdc2);
        oracleRelay.setImplementation(address(oracle1));
        oracle1.update();

        oracleRelay.setImplementation(address(oracle1));
        assertEq(oracleRelay.getRate(), 1e18, "starting rate should be 1e18");

        accountantUsdc.updateExchangeRate(1.2e6);
        oracle1.update();
        assertEq(oracleRelay.getRate(), 1.2e18, "next rate should be 1.2e18");

        oracleRelay.setImplementation(address(oracle2));
        oracle2.update();
        assertEq(oracleRelay.getRate(), 1e18, "oracle2 starting rate should be 1e18");

        accountantUsdc2.updateExchangeRate(1.2e18);
        oracle2.update();
        assertEq(oracleRelay.getRate(), 1.2e18, "oracle2 next rate should be 1.2e18");
    }

    function _startFork(string memory rpcKey) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey));
        vm.selectFork(forkId);
    }

}
