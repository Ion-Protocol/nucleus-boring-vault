// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { RedstoneStablecoinRateProvider, IPriceFeed } from "src/oracles/RedstoneStablecoinRateProvider.sol";
import { BaseScript } from "../Base.s.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { console2 } from "forge-std/console2.sol";

using StdJson for string;

contract DeployStablecoinRateProvider is BaseScript {

    // Deployer protected:  0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f
    bytes32 constant SALT = 0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f00555555555555555555cafe;
    address multisig;

    function run() public broadcast {
        bytes memory creationCode = type(RedstoneStablecoinRateProvider).creationCode;
        if (block.chainid == 999) {
            multisig = 0x413f2e80070a069eB1051772Fdc4f0af8e8303d7;
        } else {
            revert("Not a supported network, add multisig to script");
        }

        address rateProvider = CREATEX.deployCreate3(
            SALT,
            abi.encodePacked(
                creationCode,
                abi.encode(
                    multisig,
                    "RedStone Price Feed for USDC",
                    "RedStone Price Feed for USDT",
                    0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb,
                    0x4C89968338b75551243C99B452c84a01888282fD,
                    0x5e21f6530f656A38caE4F55500944753F662D184,
                    1 days
                )
            )
        );

        console2.log("rate provider: ", rateProvider);
    }

}
