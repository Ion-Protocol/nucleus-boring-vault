// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Pauser } from "src/helper/Pauser.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { BaseScript } from "../Base.s.sol";
import "@forge-std/Script.sol";
import { DistributorCodeDepositor, INativeWrapper } from "src/helper/DistributorCodeDepositor.sol";

contract DeployDistributorCodeDepositor is BaseScript {

    bytes32 constant salt = 0x1Ab5a40491925cB445fd59e607330046bEac68E5005534574445309932585859;

    address teller = 0x094c771B02094482C2D514ac46d793c8A9f5F693;
    address nativeWrapper = address(0);
    address rolesAuthority = 0xaeeC053e978A4Bfc05BEBf297250cE8528B8530d;
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
