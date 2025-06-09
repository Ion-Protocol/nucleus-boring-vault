// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { RateProviderConfig } from "./../../../src/base/Roles/RateProviderConfig.sol";
import { BaseScript } from "../Base.s.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { console2 } from "forge-std/console2.sol";

using StdJson for string;

// NOTE Currently assumes that function signature arguments are empty.
contract DeployRateProviderConfig is BaseScript {
    RateProviderConfig rateProvider;

    // deployer:            0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f00
    bytes32 constant SALT = 0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f00fcdbd6afdd472179b79b16;
    address multisig = 0x0000000000417626Ef34D62C4DC189b021603f2F;

    function run() public broadcast {
        require(multisig != address(0), "Multisig must not be set to 0 address");
        vm.prompt(
            string.concat(
                "You are about to deploy a Rate Provider Config on\nchainID ",
                vm.toString(block.chainid),
                "\nowner being set to: ",
                vm.toString(multisig),
                "\nPlease double check these values and press ENTER to continue"
            )
        );

        bytes memory creationCode = type(RateProviderConfig).creationCode;

        rateProvider =
            RateProviderConfig(CREATEX.deployCreate3(SALT, abi.encodePacked(creationCode, abi.encode(multisig))));
    }
}
