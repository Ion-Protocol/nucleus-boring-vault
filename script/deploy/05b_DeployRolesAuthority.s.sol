// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ManagerWithMerkleVerification} from "./../../src/base/Roles/ManagerWithMerkleVerification.sol";
import {BoringVault} from "./../../src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "./../../src/base/Roles/TellerWithMultiAssetSupport.sol";
import {AccountantWithRateProviders} from "./../../src/base/Roles/AccountantWithRateProviders.sol";
import {BaseScript} from "../Base.s.sol";

import {stdJson as StdJson} from "@forge-std/StdJson.sol";
import {DeployRolesAuthority} from "./05_DeployRolesAuthority.s.sol";

/**
 * @notice configures specific authority for the OP Teller
 * includes all configurations done in 05_DeployRolesAuthority
 */
contract ConfigureOPTellerAuthority is DeployRolesAuthority {
    function run() public override broadcast returns (RolesAuthority rolesAuthority){
        rolesAuthority = super.run();
    }
}
