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

    bytes32 SALT_ROLES_AUTHORITY = 0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f00323232323232323232cafe;
    bytes32 SALT_BORING_VUALT = 0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f00cafecafecafecafe32cafe;
    bytes32 SALT_MANAGER_WITH_MERKLE_VERIFICATION = 0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f00777767777677777777cafe;

    function run() public broadcast {
        // deploy a roles authority with broadcaster as the owner for now
        // we will transfer ownership to the multisig later after setting roles
        RolesAuthority rolesAuthority = RolesAuthority(
            CREATEX.deployCreate3(
                SALT_ROLES_AUTHORITY,
                abi.encodePacked(type(RolesAuthority).creationCode, abi.encode(broadcaster, Authority(address(0))))
            )
        );

        // deploy a boring vault
        address boringVaultAddress = CREATEX.deployCreate3(
            SALT_BORING_VUALT,
            abi.encodePacked(type(BoringVault).creationCode, abi.encode(getMultisig(), NAME, SYMBOL, DECIMALS))
        );
        BoringVault boringVault = BoringVault(payable(boringVaultAddress));

        // deploy a managerWithMerkleVerification
        ManagerWithMerkleVerification managerWithMerkleVerification = ManagerWithMerkleVerification(
            CREATEX.deployCreate3(
                SALT_MANAGER_WITH_MERKLE_VERIFICATION,
                abi.encodePacked(
                    type(ManagerWithMerkleVerification).creationCode,
                    abi.encode(getMultisig(), address(boringVault), BALANCER_VAULT)
                )
            )
        );

        // configure the roles
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

        rolesAuthority.transferOwnership(getMultisig());
    }

}
