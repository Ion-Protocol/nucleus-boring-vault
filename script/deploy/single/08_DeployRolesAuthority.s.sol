// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { ManagerWithMerkleVerification } from "./../../../src/base/Roles/ManagerWithMerkleVerification.sol";
import { BoringVault } from "./../../../src/base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "./../../../src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "./../../../src/base/Roles/AccountantWithRateProviders.sol";
import {AtomicSolverV4} from "./../../src/atomic-queue/AtomicSolverV4.sol";
import { BaseScript } from "../../Base.s.sol";
import { ConfigReader } from "../../ConfigReader.s.sol";
import { CrossChainTellerBase } from "../../../src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";

/**
 * NOTE Deploys with `Authority` set to zero bytes.
 */
contract DeployRolesAuthority is BaseScript {
    using StdJson for string;

    uint8 public constant STRATEGIST_ROLE = 1;
    uint8 public constant MANAGER_ROLE = 2;
    uint8 public constant TELLER_ROLE = 3;
    uint8 public constant UPDATE_EXCHANGE_RATE_ROLE = 4;
    uint8 public constant SOLVER_ROLE = 5;
    uint8 public constant QUEUE_ROLE = 6; // queue role is for calling finishSolve in solver
    uint8 public constant SOLVER_CALLER_ROLE = 7;

    function run() public virtual returns (address rolesAuthority) {
        return deploy(getConfig());
    }

    function deploy(ConfigReader.Config memory config) public virtual override broadcast returns (address) {
        // Require config Values
        require(config.boringVault.code.length != 0, "boringVault must have code");
        require(config.manager.code.length != 0, "manager must have code");
        require(config.teller.code.length != 0, "teller must have code");
        require(config.accountant.code.length != 0, "accountant must have code");
        require(config.queue.code.length != 0, "queue must have code");
        require(config.solver.code.length != 0, "solver must have code");
        require(config.boringVault != address(0), "boringVault");
        require(config.manager != address(0), "manager");
        require(config.teller != address(0), "teller");
        require(config.accountant != address(0), "accountant");
        require(config.strategist != address(0), "strategist");

        // Create Contract
        bytes memory creationCode = type(RolesAuthority).creationCode;
        RolesAuthority rolesAuthority = RolesAuthority(
            CREATEX.deployCreate3(
                config.rolesAuthoritySalt,
                abi.encodePacked(
                    creationCode,
                    abi.encode(
                        broadcaster,
                        address(0) // `Authority`
                    )
                )
            )
        );

        // Setup initial roles configurations
        // --- Users ---
        // 1. VAULT_STRATEGIST (BOT EOA)
        // 2. MANAGER (CONTRACT)
        // 3. TELLER (CONTRACT)
        // 4. EXCHANGE_RATE_BOT (BOT EOA)
        // 5. SOLVER (CONTRACT)
        // 6. QUEUE (CONTRACT)
        // 7. SOLVER_BOT (BOT EOA)
        // --- Roles ---
        // 1. STRATEGIST_ROLE
        //     - manager.manageVaultWithMerkleVerification
        //     - assigned to VAULT_STRATEGIST
        // 2. MANAGER_ROLE
        //     - boringVault.manage()
        //     - assigned to MANAGER
        // 3. TELLER_ROLE
        //     - boringVault.enter()
        //     - boringVault.exit()
        //     - assigned to TELLER
        // 5. SOLVER_ROLE
        //     - teller.bulkWithdraw
        //     - assigned to SOLVER
        // 6. QUEUE_ROLE
        //     - solver.finshSolve
        //     - assigned to QUEUE
        // 7. SOLVER_CALLER_ROLE
        //     - solver.p2pSolve
        //     - solver.redeemSolve
        //     - assigned to SOLVER_BOT
        // --- Public ---
        // 1. teller.deposit
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            config.manager,
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, config.boringVault, bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)"))), true
        );

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            config.boringVault,
            bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])"))),
            true
        );

        rolesAuthority.setRoleCapability(TELLER_ROLE, config.boringVault, BoringVault.enter.selector, true);

        rolesAuthority.setRoleCapability(TELLER_ROLE, config.boringVault, BoringVault.exit.selector, true);

        rolesAuthority.setPublicCapability(config.teller, TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(config.teller, CrossChainTellerBase.bridge.selector, true);
        rolesAuthority.setPublicCapability(config.teller, CrossChainTellerBase.depositAndBridge.selector, true);

        rolesAuthority.setRoleCapability(
            UPDATE_EXCHANGE_RATE_ROLE, config.accountant, AccountantWithRateProviders.updateExchangeRate.selector, true
        );

        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, config.teller, TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );

        rolesAuthority.setRoleCapability(QUEUE_ROLE, config.solver, AtomicSolverV4.finishSolve.selector, true
        );

        rolesAuthority.setRoleCapability(
            SOLVER_CALLER_ROLE, config.solver, AtomicSolverV4.p2pSolve.selector, true
        );

        rolesAuthority.setRoleCapability(
            SOLVER_CALLER_ROLE, config.solver, AtomicSolverV4.redeemSolve.selector, true
        );

        // --- Assign roles to users ---

        rolesAuthority.setUserRole(config.strategist, STRATEGIST_ROLE, true);

        rolesAuthority.setUserRole(config.manager, MANAGER_ROLE, true);

        rolesAuthority.setUserRole(config.teller, TELLER_ROLE, true);

        rolesAuthority.setUserRole(config.exchangeRateBot, UPDATE_EXCHANGE_RATE_ROLE, true);

        rolesAuthority.setUserRole(config.solver, SOLVER_ROLE, true);

        rolesAuthority.setUserRole(config.queue, QUEUE_ROLE, true);

        rolesAuthority.setUserRole(config.solverBot, SOLVER_CALLER_ROLE, true);

        // Post Deploy Checks
        require(
            rolesAuthority.doesUserHaveRole(config.strategist, STRATEGIST_ROLE),
            "strategist should have STRATEGIST_ROLE"
        );
        require(rolesAuthority.doesUserHaveRole(config.manager, MANAGER_ROLE), "manager should have MANAGER_ROLE");
        require(rolesAuthority.doesUserHaveRole(config.teller, TELLER_ROLE), "teller should have TELLER_ROLE");
        require(
            rolesAuthority.doesUserHaveRole(config.exchangeRateBot, UPDATE_EXCHANGE_RATE_ROLE),
            "exchangeRateBot should have UPDATE_EXCHANGE_RATE_ROLE"
        );
        require(rolesAuthority.doesUserHaveRole(config.solver, SOLVER_ROLE), "solver should have SOLVER_ROLE");
        require(rolesAuthority.doesUserHaveRole(config.queue, QUEUE_ROLE), "queue should have QUEUE_ROLE");
        require(
            rolesAuthority.doesUserHaveRole(config.solverBot, SOLVER_CALLER_ROLE),
            "solverBot should have SOLVER_CALLER_ROLE"
        );
        require(
            rolesAuthority.canCall(
                config.strategist,
                config.manager,
                ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector
            ),
            "strategist should be able to call manageVaultWithMerkleVerification"
        );
        require(
            rolesAuthority.canCall(
                config.manager, config.boringVault, bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)")))
            ),
            "manager should be able to call boringVault.manage"
        );
        require(
            rolesAuthority.canCall(
                config.manager,
                config.boringVault,
                bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])")))
            ),
            "manager should be able to call boringVault.manage"
        );
        require(
            rolesAuthority.canCall(config.teller, config.boringVault, BoringVault.enter.selector),
            "teller should be able to call boringVault.enter"
        );
        require(
            rolesAuthority.canCall(config.teller, config.boringVault, BoringVault.exit.selector),
            "teller should be able to call boringVault.exit"
        );
        require(
            rolesAuthority.canCall(
                config.exchangeRateBot, config.accountant, AccountantWithRateProviders.updateExchangeRate.selector
            ),
            "exchangeRateBot should be able to call accountant.updateExchangeRate"
        );
        require(
            rolesAuthority.canCall(config.solver, config.teller, TellerWithMultiAssetSupport.bulkWithdraw.selector),
            "solver should be able to call teller.bulkWithdraw"
        );
        require(
            rolesAuthority.canCall(config.queue, config.solver, AtomicSolverV4.finishSolve.selector),
            "queue should be able to call solver.finishSolve"
        );
        require(
            rolesAuthority.canCall(config.solverBot, config.solver, AtomicSolverV4.p2pSolve.selector),
            "solverBot should be able to call solver.p2pSolve"
        );
        require(
            rolesAuthority.canCall(config.solverBot, config.solver, AtomicSolverV4.redeemSolve.selector),
            "solverBot should be able to call solver.redeemSolve"
        );
        require(
            rolesAuthority.canCall(address(1), config.teller, TellerWithMultiAssetSupport.deposit.selector),
            "anyone should be able to call teller.deposit"
        );

        return address(rolesAuthority);
    }
}
