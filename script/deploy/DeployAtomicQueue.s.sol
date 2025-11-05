// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AtomicQueue } from "./../../src/atomic-queue/AtomicQueue.sol";
import { BaseScript } from "../Base.s.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";

using StdJson for string;

bytes32 constant SALT = 0x5bac910c72debe007de61c000000000000000000000000000000000000000000;

contract DeployAtomicQueue is BaseScript {

    function run() public broadcast returns (AtomicQueue atomicQueue) {
        bytes memory creationCode = type(AtomicQueue).creationCode;

        atomicQueue = AtomicQueue(CREATEX.deployCreate3(SALT, creationCode));
    }

}
