// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { RedstoneStablecoinRateProvider, IPriceFeed } from "src/oracles/RedstoneStablecoinRateProvider.sol";

contract RedstoneStablecoinOracleTestUSDT is Test, MainnetAddresses {

    RedstoneStablecoinRateProvider rateProvider;
    // 4/29/2025, 7:51:00 PM | there's no date since contract creation to test the lower bound
    uint256 internal constant BLOCK_NUMBER = 3_161_820;

    function setUp() external {
        _startFork("HL_RPC_URL", BLOCK_NUMBER);
        rateProvider = new RedstoneStablecoinRateProvider(
            address(this),
            "RedStone Price Feed for USDC",
            "RedStone Price Feed for USDT",
            ERC20(0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb),
            IPriceFeed(0x4C89968338b75551243C99B452c84a01888282fD),
            IPriceFeed(0x5e21f6530f656A38caE4F55500944753F662D184),
            1 days
        );
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }

    function testGetRateUSDT() external {
        uint256 expectedRate = 999_400;
        uint256 rate = rateProvider.getRate();
        assertGt(rate, rateProvider.lowerBound());
    }

}

contract RedstoneStablecoinOracleTestUSDe is Test, MainnetAddresses {

    RedstoneStablecoinRateProvider rateProvider;
    // 4/28/2025, 12:00:00 AM | A date when USDe is depegged and rate tests lower bound
    uint256 internal constant BLOCK_NUMBER = 3_080_259;

    function setUp() external {
        _startFork("HL_RPC_URL", BLOCK_NUMBER);
        rateProvider = new RedstoneStablecoinRateProvider(
            address(this),
            "RedStone Price Feed for USDC",
            "RedStone Price Feed for USDe",
            ERC20(0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34),
            IPriceFeed(0x4C89968338b75551243C99B452c84a01888282fD),
            IPriceFeed(0xcA727511c9d542AAb9eF406d24E5bbbE4567c22d),
            1 days
        );
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }

    function testGetRateUSDe() external {
        uint256 expectedRate = 999_380_551_276_162_675;
        vm.expectRevert(
            abi.encodeWithSelector(
                RedstoneStablecoinRateProvider.BoundsViolated.selector, expectedRate, rateProvider.lowerBound()
            )
        );
        rateProvider.getRate();
    }

}

contract RedstoneStablecoinOracleTestSetToOne is Test, MainnetAddresses {

    RedstoneStablecoinRateProvider rateProviderUSDT;
    RedstoneStablecoinRateProvider rateProviderUSDe;
    // Jun 3, 2025, all are above 1
    uint256 internal constant BLOCK_NUMBER = 4_840_922;

    function setUp() external {
        _startFork("HL_RPC_URL", BLOCK_NUMBER);
        rateProviderUSDe = new RedstoneStablecoinRateProvider(
            address(this),
            "RedStone Price Feed for USDC",
            "RedStone Price Feed for USDe",
            ERC20(0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34),
            IPriceFeed(0x4C89968338b75551243C99B452c84a01888282fD),
            IPriceFeed(0xcA727511c9d542AAb9eF406d24E5bbbE4567c22d),
            1 days
        );
        rateProviderUSDT = new RedstoneStablecoinRateProvider(
            address(this),
            "RedStone Price Feed for USDC",
            "RedStone Price Feed for USDT",
            ERC20(0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb),
            IPriceFeed(0x4C89968338b75551243C99B452c84a01888282fD),
            IPriceFeed(0x5e21f6530f656A38caE4F55500944753F662D184),
            1 days
        );
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }

    function testGetRateUSDT() external {
        uint256 rate = rateProviderUSDT.getRate();
        assertEq(rate, 10 ** 6);
    }

    // USDe has 18 decimals
    function testGetRateUSDe() external {
        uint256 rate = rateProviderUSDe.getRate();
        assertEq(rate, 10 ** 18);
    }

}
