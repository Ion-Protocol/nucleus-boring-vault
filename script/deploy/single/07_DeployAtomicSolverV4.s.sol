// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AtomicSolverV4 } from "./../../src/atomic-queue/AtomicSolverV4.sol";
import { BaseScript } from "./../Base.s.sol";
import { stdJson as StdJson } from "forge-std/StdJson.sol";
import { ConfigReader } from "../../ConfigReader.s.sol";

contract DeployAtomicSolverV4 is BaseScript {
    using StdJson for string;

    function run() public returns (address manager) {
        manager = deploy(getConfig());
    }

    function deploy(ConfigReader.Config memory config) public override broadcast returns (address) {
        // Require config Values
        require(config.solverSalt != bytes32(0), "solver salt must not be zero");

        // Create Contract
        bytes memory creationCode = type(AtomicSolverV4).creationCode;

        solver = AtomicSolverV4(
            CREATEX.deployCreate3(config.solverSalt, abi.encodePacked(creationCode, abi.encode(broadcaster)))
        );

        return address(solver);
    }
}
