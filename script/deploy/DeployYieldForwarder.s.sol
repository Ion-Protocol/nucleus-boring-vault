// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.8.21;

import { console } from "forge-std/console.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { RolesAuthority } from "src/base/Roles/RolesAuthority.sol";
import { stdJson } from "@forge-std/Script.sol";
import { BaseScript } from "script/Base.s.sol";

contract DeployYieldForwarder is BaseScript {

    string constant NAME = "Boring Vault";
    string constant SYMBOL = "BV";
    address constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant MANAGER_ADDRESS = address(0);

    function run() public broadcast {
        // deploy a roles authority
        RolesAuthority rolesAuthority = new RolesAuthority(getMultisig(), Authority(address(0)));

        // deploy a boring vault
        BoringVault boringVault = new BoringVault(getMultisig(), NAME, SYMBOL, 18);

        // deploy a managerWithMerkleVerification
        ManagerWithMerkleVerification managerWithMerkleVerification =
            new ManagerWithMerkleVerification(getMultisig(), address(boringVault), BALANCER_VAULT);

        // configure the roles
        rolesAuthority.setRoleCapability(MANAGER_ROLE, address(boringVault), BoringVault.manage.selector, true);
        rolesAuthority.setUserRole(MANAGER_ADDRESS, MANAGER_ROLE, true);
    }

}
