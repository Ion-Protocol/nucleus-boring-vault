// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseScript } from "./../../Base.s.sol";
import { ConfigReader } from "../../ConfigReader.s.sol";
import { EquivalentExchangeUManager } from "src/micro-managers/EquivalentExchangeUManager.sol";
import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { console } from "@forge-std/console.sol";
import "src/helper/Constants.sol";

/**
 * Deploy and wire the EquivalentExchangeUManager for the configured boring vault.
 *
 * @dev The UManager drives `manager.manageVaultWithMerkleVerification`, so it must hold STRATEGIST_ROLE
 * in the shared RolesAuthority. That authority is only broadcaster-owned until
 * `11_SetAuthorityAndTransferOwnerships` hands it to the multisig, so this step MUST run BEFORE step 11
 * (see the ordering comment in deployAll.s.sol). It reverts if the RolesAuthority has already been handed
 * off, to fail loudly rather than deploy an unusable UManager.
 *
 * Access model configured here:
 *   - owner  = protocolAdmin (multisig): the only caller of the owner-gated `setBasketTokens`.
 *   - authority = shared RolesAuthority, with STRATEGIST_ROLE granted the capability to call `execute`.
 *     The strategist EOA (config.strategist, already a STRATEGIST_ROLE holder from step 07) can therefore
 *     call `execute` but NOT `setBasketTokens`.
 *   - the UManager itself is granted STRATEGIST_ROLE so it may call the merkle-verification manager.
 *
 * If a basket is provided in config (parallel `basketTokens` / `basketOracles` / `basketRateDecimals`
 * arrays), it is wired via `setBasketTokens` while the broadcaster still owns the UManager, i.e. before the
 * ownership transfer, mirroring how the Accountant's rate providers are set during deploy. The basket is
 * optional; an empty basket leaves the UManager for the multisig to configure later. Each non-zero oracle
 * is required to return a positive `getRate()` at deploy time so a misconfigured basket fails the deploy
 * rather than the first `execute`.
 */
contract DeployEquivalentExchangeUManager is BaseScript {

    function run() public returns (address) {
        return deploy(getConfig());
    }

    function _deploy(ConfigReader.Config memory config) public override broadcast returns (address) {
        // Require config values.
        require(config.boringVault != address(0), "boringVault must not be zero address");
        require(config.boringVault.code.length != 0, "boringVault must have code");
        require(config.manager != address(0), "manager must not be zero address");
        require(config.manager.code.length != 0, "manager must have code");
        require(config.rolesAuthority != address(0), "rolesAuthority must not be zero address");
        require(config.rolesAuthority.code.length != 0, "rolesAuthority must have code");
        require(config.strategist != address(0), "strategist must not be zero address");
        require(config.protocolAdmin != address(0), "protocolAdmin must not be zero address");

        RolesAuthority rolesAuthority = RolesAuthority(config.rolesAuthority);

        // The role wiring below (setRoleCapability / setUserRole) requires the broadcaster to still own the
        // RolesAuthority. Step 11 transfers it to the multisig, so this step must run before that handoff.
        require(
            rolesAuthority.owner() == broadcaster,
            "rolesAuthority must still be broadcaster-owned; run this step before 11_SetAuthorityAndTransferOwnerships"
        );

        bytes32 salt =
            makeSalt(broadcaster, false, string(abi.encodePacked(config.nameEntropy, ":EquivalentExchangeUManager")));

        // Deploy owned by the broadcaster so it can wire the UManager's authority below before handing
        // ownership to the multisig. `manager` and `boringVault` are the immutables the UManager drives.
        bytes memory creationCode = type(EquivalentExchangeUManager).creationCode;
        EquivalentExchangeUManager uManager = EquivalentExchangeUManager(
            CREATEX.deployCreate3(
                salt, abi.encodePacked(creationCode, abi.encode(broadcaster, config.manager, config.boringVault))
            )
        );

        // Point the UManager at the shared RolesAuthority so role capabilities gate its own external
        // functions. Its constructor hardcodes Authority(0) (owner-only), so this is required for the
        // strategist EOA to reach `execute`.
        uManager.setAuthority(rolesAuthority);

        // `execute` is callable by STRATEGIST_ROLE holders (e.g. the strategist EOA). `setBasketTokens` is
        // intentionally given no role capability, so it stays owner-only (the multisig, set below).
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE, address(uManager), EquivalentExchangeUManager.execute.selector, true
        );

        // Grant the UManager STRATEGIST_ROLE so it may call manager.manageVaultWithMerkleVerification
        // (that capability is granted to STRATEGIST_ROLE in 07_DeployRolesAuthority).
        rolesAuthority.setUserRole(address(uManager), STRATEGIST_ROLE, true);

        // Configure the accounting basket (if any) while the broadcaster still owns the UManager. This must
        // precede the ownership transfer below, since setBasketTokens is owner-gated and ownership moves to
        // the multisig next.
        _configureBasketIfProvided(uManager, config);

        // Hand ownership to the multisig. From here, only the multisig can call the owner-gated
        // `setBasketTokens`; the broadcaster retains nothing.
        uManager.transferOwnership(config.protocolAdmin);

        // Post-deploy checks.
        require(address(uManager.authority()) == config.rolesAuthority, "uManager authority should be rolesAuthority");
        require(uManager.owner() == config.protocolAdmin, "uManager owner should be protocolAdmin");
        require(
            rolesAuthority.doesUserHaveRole(address(uManager), STRATEGIST_ROLE), "uManager should have STRATEGIST_ROLE"
        );
        require(
            rolesAuthority.canCall(config.strategist, address(uManager), EquivalentExchangeUManager.execute.selector),
            "strategist should be able to call uManager.execute"
        );
        require(
            rolesAuthority.canCall(
                address(uManager),
                config.manager,
                ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector
            ),
            "uManager should be able to drive the merkle-verification manager"
        );

        console.log("Equivalent Exchange UManager: ", address(uManager));
        console.log("  owner (multisig):    ", config.protocolAdmin);
        console.log("  execute caller (EOA):", config.strategist);

        return address(uManager);
    }

    /**
     * @notice Builds the accounting basket from the config's parallel arrays and sets it on the UManager.
     * @dev No-op when no basket is configured. Called while the broadcaster still owns the UManager, so the
     * owner-gated `setBasketTokens` succeeds; it must run before ownership is transferred to the multisig.
     * The ConfigReader has already validated that the three basket arrays are equal length.
     * @param uManager The freshly deployed, broadcaster-owned UManager.
     * @param config Deployment config carrying the optional basket arrays.
     */
    function _configureBasketIfProvided(
        EquivalentExchangeUManager uManager,
        ConfigReader.Config memory config
    )
        internal
    {
        uint256 length = config.equivalentExchangeUManagerBasketTokens.length;
        if (length == 0) {
            console.log("  basket: none configured (multisig can set it later via setBasketTokens)");
            return;
        }

        EquivalentExchangeUManager.BasketToken[] memory basket = new EquivalentExchangeUManager.BasketToken[](length);
        for (uint256 i; i < length; ++i) {
            address token = config.equivalentExchangeUManagerBasketTokens[i];
            address oracle = config.equivalentExchangeUManagerBasketOracles[i];
            uint256 rateDecimals = config.equivalentExchangeUManagerBasketRateDecimals[i];

            require(token != address(0), "basket token must not be zero address");
            require(token.code.length != 0, "basket token must have code");
            // rateDecimals is a uint8 on the struct; reject anything that would silently truncate.
            require(rateDecimals <= type(uint8).max, "basket rateDecimals out of uint8 range");

            if (oracle != address(0)) {
                require(oracle.code.length != 0, "basket oracle must have code");
                // Liveness/sanity: a live oracle must return a positive rate now, so a misconfigured basket
                // fails the deploy rather than the strategist's first execute(). setBasketTokens itself only
                // reads oracles at execute time, so this check is additive.
                require(IRateProvider(oracle).getRate() > 0, "basket oracle getRate() must be positive");
            }
            // The (oracle == 0) XOR (rateDecimals == 0) rule and the duplicate-token rule are enforced by
            // setBasketTokens (OracleDecimalsMismatch / DuplicateToken), so they are not duplicated here.

            basket[i] = EquivalentExchangeUManager.BasketToken({
                token: ERC20(token), oracle: IRateProvider(oracle), rateDecimals: uint8(rateDecimals)
            });
        }

        uManager.setBasketTokens(basket);

        // Post-check: the stored basket matches the configured tokens exactly.
        require(uManager.getBasketTokens().length == length, "basket length mismatch after setBasketTokens");
        for (uint256 i; i < length; ++i) {
            require(
                uManager.isBasketToken(ERC20(config.equivalentExchangeUManagerBasketTokens[i])),
                "configured basket token missing after setBasketTokens"
            );
        }
        console.log("  basket tokens configured: ", length);
    }

}
