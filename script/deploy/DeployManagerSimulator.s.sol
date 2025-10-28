// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.8.21;

import { console } from "forge-std/console.sol";
import { ManagerSimulator } from "src/base/Roles/ManagerSimulator.sol";
import { stdJson } from "@forge-std/Script.sol";
import { BaseScript } from "script/Base.s.sol";

contract DeployManagerSimulator is BaseScript {

    // Deployer protected:  0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f
    bytes32 constant SALT = 0xe73b8960335581747836c0133959a00ff523cbf8ab66f509f0a7e31c2147cafe;

    constructor() BaseScript() { }

    function run(uint8 nativeDecimalsForThisChain) public broadcast {
        bytes memory creationCode = type(ManagerSimulator).creationCode;
        address simulator =
            CREATEX.deployCreate3(SALT, abi.encodePacked(creationCode, abi.encode(nativeDecimalsForThisChain)));

        console.log(simulator);
        console.log("Simulator deployed. Remember to grant MANAGE role for all vaults on this chain");
    }

}
