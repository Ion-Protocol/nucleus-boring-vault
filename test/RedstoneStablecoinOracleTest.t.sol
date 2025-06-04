// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { RedstoneStablecoinRateProvider, IPriceFeed } from "src/oracles/RedstoneStablecoinRateProvider.sol";

contract RedstoneStablecoinOracleTest is Test, MainnetAddresses {
    RedstoneStablecoinRateProvider rateProvider;

    function setUp() external {
        rateProvider = new RedstoneStablecoinRateProvider(
            address(this),
            "RedStone Price Feed for USDC",
            "RedStone Price Feed for USDT",
            IPriceFeed(0x4C89968338b75551243C99B452c84a01888282fD),
            IPriceFeed(0x5e21f6530f656A38caE4F55500944753F662D184),
            1 days,
            6
        );
    }

    function testGetRate() external {
        console.log(rateProvider.getRate());
    }
}
