import { BaseScript } from "../../Base.s.sol";
import { TELLER_ROLE, SOLVER_ROLE } from "../single/06_DeployRolesAuthority.s.sol";

import { TellerWithMultiAssetSupport } from "../../../src/base/Roles/TellerWithMultiAssetSupport.sol";
import { CrossChainTellerBase } from "../../../src/base/Roles/CrossChain/CrossChainTellerBase.sol";

import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";

// forge script script/deploy/ --sig run(address, address) <oldTellerAddress> <newTellerAddress> --rpc-url <RPC_URL>
contract CheckTellerUpgrade is BaseScript {

    function run(address oldTeller, address newTeller) public {
        require(oldTeller != address(0));
        require(newTeller != address(0));

        TellerWithMultiAssetSupport typedOldTeller = TellerWithMultiAssetSupport(oldTeller);
        TellerWithMultiAssetSupport typedNewTeller = TellerWithMultiAssetSupport(newTeller);

        RolesAuthority authority = RolesAuthority(address(typedOldTeller.authority()));

        require(authority == typedNewTeller.authority());
        require(typedOldTeller.vault() == typedNewTeller.vault());
        require(typedOldTeller.accountant() == typedNewTeller.accountant());

        // --- Old Teller Must Be Disabled ---

        // Public capabilities.

        // functions that were previously public
        require(
            !authority.isCapabilityPublic(oldTeller, TellerWithMultiAssetSupport.deposit.selector),
            "oldTeller deposit must not be public"
        );
        require(
            !authority.isCapabilityPublic(oldTeller, CrossChainTellerBase.bridge.selector),
            "oldTeller bridge must not be public"
        );
        require(
            !authority.isCapabilityPublic(oldTeller, CrossChainTellerBase.depositAndBridge.selector),
            "oldTeller depositAndBridge must not be public"
        );

        // functions that should never be public
        require(
            !authority.isCapabilityPublic(oldTeller, TellerWithMultiAssetSupport.refundDeposit.selector),
            "oldTeller refundDeposit must not be public"
        );
        require(
            !authority.isCapabilityPublic(oldTeller, TellerWithMultiAssetSupport.depositWithPermit.selector),
            "oldTeller depositWithPermit must not be public"
        );
        require(
            !authority.isCapabilityPublic(oldTeller, TellerWithMultiAssetSupport.bulkDeposit.selector),
            "oldTeller bulkDeposit must not be public"
        );
        require(
            !authority.isCapabilityPublic(oldTeller, TellerWithMultiAssetSupport.bulkWithdraw.selector),
            "oldTeller bulkWithdraw must not be public"
        );

        require(typedOldTeller.isPaused(), "oldTeller must be paused");

        // roles
        require(!authority.doesUserHaveRole(oldTeller, TELLER_ROLE), "oldTeller must not have the TELLER_ROLE");
        require(
            !authority.doesRoleHaveCapability(
                SOLVER_ROLE, oldTeller, TellerWithMultiAssetSupport.bulkWithdraw.selector
            ),
            "SOLVER_ROLE must not be able to call oldTeller's bulkWithdraw"
        );

        // --- New Teller Must Be Enabled---
        // Public capabilities.
        require(
            authority.isCapabilityPublic(newTeller, TellerWithMultiAssetSupport.deposit.selector),
            "newTeller deposit must be public"
        );
        require(
            authority.isCapabilityPublic(newTeller, CrossChainTellerBase.bridge.selector),
            "newTeller bridge must be public"
        );
        require(
            authority.isCapabilityPublic(newTeller, CrossChainTellerBase.depositAndBridge.selector),
            "newTeller depositAndBridge must be public"
        );

        // functions that should never be public
        require(
            !authority.isCapabilityPublic(newTeller, TellerWithMultiAssetSupport.refundDeposit.selector),
            "newTeller refundDeposit must not be public"
        );
        require(
            !authority.isCapabilityPublic(newTeller, TellerWithMultiAssetSupport.depositWithPermit.selector),
            "newTeller depositWithPermit must not be public"
        );
        require(
            !authority.isCapabilityPublic(newTeller, TellerWithMultiAssetSupport.bulkDeposit.selector),
            "newTeller bulkDeposit must not be public"
        );
        require(
            !authority.isCapabilityPublic(newTeller, TellerWithMultiAssetSupport.bulkWithdraw.selector),
            "newTeller bulkWithdraw must not be public"
        );

        require(!typedNewTeller.isPaused(), "newTeller must not be paused");

        // roles
        require(authority.doesUserHaveRole(newTeller, TELLER_ROLE), "newTeller must have the TELLER_ROLE");
        require(
            authority.doesRoleHaveCapability(SOLVER_ROLE, newTeller, TellerWithMultiAssetSupport.bulkWithdraw.selector),
            "SOLVER_ROLE must be able to call newTeller's bulkWithdraw"
        );
    }

}
