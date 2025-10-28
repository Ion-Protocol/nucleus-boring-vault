// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Pauser } from "src/helper/Pauser.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { BaseScript } from "../Base.s.sol";
import "@forge-std/Script.sol";

contract DeployPauser is BaseScript {

    // State variables for deployed contracts
    Pauser internal pauser;

    //0xe5CcB29Cb9C886da329098A184302E2D5Ff0cD9E
    bytes32 constant salt = 0xe5CcB29Cb9C886da329098A184302E2D5Ff0cD9Eff8888845454545454545455;
    address constant admin = 0x6d0C5a20ac08ED00256aD224F74Ca53afF3D011d;

    function run() external broadcast {
        address[] memory approvedPausers = new address[](2);

        approvedPausers[0] = 0xe5CcB29Cb9C886da329098A184302E2D5Ff0cD9E;
        approvedPausers[1] = 0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f;

        bytes memory creationCode = type(Pauser).creationCode;
        pauser = Pauser(CREATEX.deployCreate3(salt, abi.encodePacked(creationCode, abi.encode(admin, approvedPausers))));
        require(pauser.owner() == admin);
        require(pauser.isApprovedPauser(approvedPausers[0]));
        require(pauser.isApprovedPauser(approvedPausers[1]));
        console.log(address(pauser));
    }

}
