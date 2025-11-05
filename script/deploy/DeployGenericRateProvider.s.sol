// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { GenericRateProvider } from "./../../src/helper/GenericRateProvider.sol";
import { BaseScript } from "../Base.s.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { console2 } from "forge-std/console2.sol";

using StdJson for string;

// NOTE Currently assumes that function signature arguments are empty.
contract DeployGenericRateProvider is BaseScript {

    string configPath = "./deployment-config/rates/DeployGenericRateProvider.json";
    string config = vm.readFile(configPath);

    uint256 expectedMin = config.readUint(".expectedMin");
    uint256 expectedMax = config.readUint(".expectedMax");
    address target = config.readAddress(".target");
    string signature = config.readString(".signature");
    bytes32 salt = config.readBytes32(".salt");

    function run() public broadcast returns (GenericRateProvider rateProvider) {
        bytes4 functionSig = bytes4(keccak256(bytes(signature)));
        console2.logBytes4(functionSig);

        bytes memory creationCode = type(GenericRateProvider).creationCode;

        rateProvider = GenericRateProvider(
            CREATEX.deployCreate3(
                salt, abi.encodePacked(creationCode, abi.encode(target, functionSig, 0, 0, 0, 0, 0, 0, 0, 0))
            )
        );

        uint256 rate = rateProvider.getRate();

        console2.log("rate: ", rate);

        require(rate != 0, "rate must not be zero");
        require(rate >= expectedMin, "rate must be greater than or equal to min");
        require(rate <= expectedMax, "rate must be less than or equal to max");
    }

}
