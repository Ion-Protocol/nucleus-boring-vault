// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Pauser } from "src/helper/Pauser.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { BaseScript } from "../Base.s.sol";
import "@forge-std/Script.sol";
import { DistributorCodeDepositor, INativeWrapper } from "src/helper/DistributorCodeDepositor.sol";

contract DeployDistributorCodeDepositor is BaseScript {

    bytes32 constant salt = 0x12341ed9cb38ae1b15016c6ed9f88e247f2af76f008234578975309999585858;

    address teller = 0x5D19246327ED91DA93080E7eC9B96Bf2a93ff392;
    address nativeWrapper = address(0);
    address rolesAuthority = 0x368B75a32Db53332bd9916Cf27272bf9696BCc45;
    bool isNativeDepositSupported = false;
    address owner = getMultisig();

    function run() external broadcast {
        bytes memory creationCode = type(DistributorCodeDepositor).creationCode;
        address distributorCodeDepositor =
            (CREATEX.deployCreate3(
                salt,
                abi.encodePacked(
                    creationCode, abi.encode(teller, nativeWrapper, rolesAuthority, isNativeDepositSupported, owner)
                )
            ));
        require(DistributorCodeDepositor(distributorCodeDepositor).owner() == getMultisig());
        console.log(distributorCodeDepositor);
    }

}
