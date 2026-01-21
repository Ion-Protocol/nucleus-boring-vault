// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IonPoolDecoderAndSanitizer } from "../../src/base/DecodersAndSanitizers/IonPoolDecoderAndSanitizer.sol";
import { BaseScript } from "../Base.s.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { ConfigReader } from "../ConfigReader.s.sol";

contract DeployDecoderAndSanitizer is BaseScript {

    using StdJson for string;

    function run() public returns (address decoder) {
        return deploy(getConfig());
    }

    function deploy(ConfigReader.Config memory config) public override broadcast returns (address) {
        // Require config Values
        require(config.boringVault.code.length != 0, "boringVault must have code");
        require(config.decoderSalt != bytes32(0), "decoder salt must not be zero");
        require(config.boringVault != address(0), "boring vault must be set");

        // Create Contract
        bytes memory creationCode = type(IonPoolDecoderAndSanitizer).creationCode;
        IonPoolDecoderAndSanitizer decoder = IonPoolDecoderAndSanitizer(
            CREATEX.deployCreate3(config.decoderSalt, abi.encodePacked(creationCode, abi.encode(config.boringVault)))
        );

        return address(decoder);
    }

}
