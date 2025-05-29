// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.8.21;

import { console } from "forge-std/console.sol";
import { ManagerWithTokenBalanceVerification } from "src/base/Roles/ManagerWithTokenBalanceVerification.sol";
import { stdJson } from "@forge-std/Script.sol";
import { BaseScript } from "script/Base.s.sol";

contract DeployManagerWithTokenBalanceVerification is BaseScript {
    address immutable EXPECTED;

    // Deployer protected:  0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f
    bytes32 constant SALT = 0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f008085885858585858585858;

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

    function getMultisig() internal returns (address) {
        if (block.chainid == 1) {
            return 0x0000000000417626Ef34D62C4DC189b021603f2F;
        } else if (block.chainid == 1329) {
            return 0xF2dE1311C5b2C1BD94de996DA13F80010453e505;
        } else if (block.chainid == 42_161) {
            return 0x08f6f6dD5C9B33015124e1Ea4Ea1e0B11DB342FB;
        } else if (block.chainid == 1923) {
            return 0xc6cC90808A3434DF28028824Fd3cefcaE4A93A88;
        } else if (block.chainid == 98_866) {
            return 0x823873F5E05564a2F8374c56053ac65E3Add061b;
        } else if (block.chainid == 999) {
            return 0x413f2e80070a069eB1051772Fdc4f0af8e8303d7;
        } else {
            revert("bad chain id");
        }
    }
}
