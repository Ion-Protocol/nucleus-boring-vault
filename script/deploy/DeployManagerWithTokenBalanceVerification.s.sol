// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.8.21;

import { console } from "forge-std/console.sol";
import { ManagerWithTokenBalanceVerification } from "src/base/Roles/ManagerWithTokenBalanceVerification.sol";
import { stdJson } from "@forge-std/Script.sol";
import { BaseScript } from "script/Base.s.sol";

contract DeployManagerWithTokenBalanceVerification is BaseScript {

    address immutable EXPECTED;

    // Deployer protected:  0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f
    bytes32 constant SALT = 0x12341ed9cb38ae1b15016c6ed9f88e247f2af76f008085885858585858585858;

    constructor() BaseScript() {
        EXPECTED = vm.envAddress("SIMULATOR");
    }

    function run(uint8 nativeDecimalsForThisChain) public broadcast {
        address multisig = getMultisig();
        console.log("setting ownership to: ", multisig);
        require(EXPECTED.code.length == 0, "Simulator already exists on this chain");

        bytes memory creationCode = type(ManagerWithTokenBalanceVerification).creationCode;
        address simulator = CREATEX.deployCreate3(
            SALT, abi.encodePacked(creationCode, abi.encode(nativeDecimalsForThisChain, multisig))
        );
        console.log(simulator);
        require(address(simulator) == EXPECTED, "address is not expected");
        require(ManagerWithTokenBalanceVerification(simulator).owner() == multisig, "Not owner");
        console.log("Simulator deployed. Remember to grant MANAGE role for all vaults on this chain");
    }

}
