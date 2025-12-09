// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Pauser } from "src/helper/Pauser.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { BaseScript } from "../Base.s.sol";
import "@forge-std/Script.sol";
import { DistributorCodeDepositor, INativeWrapper } from "src/helper/DistributorCodeDepositor.sol";

contract DeployDistributorCodeDepositor is BaseScript {

    bytes32 constant salt = 0x1Ab5a40491925cB445fd59e607330046bEac68E500553457444530993258585a;

    address teller = 0x6a12293FE7395f3E1FFcCF6E689A3a2c6926166D;
    address nativeWrapper = address(0);
    address rolesAuthority = 0xc34Fd9a670Aed5f67B7033274B4E91804303d037;
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
