// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {AtomicQueueV2} from "./../../src/atomic-queue/AtomicQueueV2.sol";
import {BaseScript} from "./../Base.s.sol";
import {stdJson as StdJson} from "forge-std/StdJson.sol";
import { ConfigReader } from "../../ConfigReader.s.sol";

contract DeployAtomicQueueV2 is BaseScript {
    using StdJson for string;

    function run() public returns (address manager) {
        manager = deploy(getConfig());
    }

    function deploy(ConfigReader.Config memory config) public override broadcast returns (address) {
        // Require config Values
        require(config.queueSalt != bytes32(0), "queue salt must not be zero");

        // Create Contract
        bytes memory creationCode = type(AtomicQueueV2).creationCode;

        queue = AtomicQueueV2(
            CREATEX.deployCreate3(
                config.queueSalt,
                abi.encodePacked(creationCode)
            )
        );

        return address(queue);
    }
}