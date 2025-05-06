// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.8.21;

import { console } from "forge-std/console.sol";
import { ManagerSimulator } from "src/base/Roles/ManagerSimulator.sol";
import { stdJson } from "@forge-std/Script.sol";
import { BaseScript } from "script/Base.s.sol";

contract DeployCustomCreateX is BaseScript {
    address immutable EXPECTED;

    // Deployer protected: 0x04354e44ed31022716e77eC6320C04Eda153010c
    bytes32 constant SALT = 0x04354e44ed31022716e77eC6320C04Eda153010c007000000000000000000000;

    constructor() BaseScript() {
        EXPECTED = vm.envAddress("SIMULATOR");
    }

    function run() public broadcast {
        require(EXPECTED.code.length == 0, "Simulator already exists on this chain");

        bytes memory creationCode = type(ManagerSimulator).creationCode;
        address simulator = CREATEX.deployCreate3(SALT, abi.encodePacked(creationCode));

        console.log(simulator);
        require(address(simulator) == EXPECTED, "address is not expected");
        console.log("Simulator deployed. Remember to grant MANAGE role for all vaults on this chain");
    }
}
