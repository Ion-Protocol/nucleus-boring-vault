// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.8.21;

import { console } from "forge-std/console.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { stdJson } from "@forge-std/Script.sol";
import { BaseScript } from "script/Base.s.sol";
import "src/helper/Constants.sol";

contract DeployYieldForwarder is BaseScript {

    string constant NAME = "YieldForwarder";
    string constant SYMBOL = "YF";
    address constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant STRATEGIST_ADDRESS = 0x000054f89dCC1248716804E7eF5c5E225FE3a000;
    uint8 constant DECIMALS = 6;

    function run() public broadcast {
        // deploy a roles authority
        RolesAuthority rolesAuthority = new RolesAuthority(getMultisig(), Authority(address(0)));

        // deploy a boring vault
        BoringVault boringVault = new BoringVault(getMultisig(), NAME, SYMBOL, DECIMALS);

        // deploy a managerWithMerkleVerification
        ManagerWithMerkleVerification managerWithMerkleVerification =
            new ManagerWithMerkleVerification(getMultisig(), address(boringVault), BALANCER_VAULT);

        // configure the roles
        bytes4 manageSelector = bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)")));
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(boringVault),
            bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)"))),
            true
        );

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(boringVault),
            bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])"))),
            true
        );
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(managerWithMerkleVerification),
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );

        rolesAuthority.setUserRole(address(managerWithMerkleVerification), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(STRATEGIST_ADDRESS, STRATEGIST_ROLE, true);
    }

}
