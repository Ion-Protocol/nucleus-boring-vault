// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseScript } from "../Base.s.sol";
import { ConfigReader } from "../ConfigReader.s.sol";
import { CowSwapHelper } from "src/helper/cow-swap/CowSwapHelper.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @notice Deploys the {CowSwapHelper} for the configured BoringVault via CreateX CREATE3.
 * @dev The helper becomes the CoW Protocol order owner on behalf of a specific BoringVault, caching the
 * settlement contract's `vaultRelayer` and `domainSeparator` at construction. The BoringVault address is
 * read from the deployment config (`.boringVault.address`); SETTLEMENT is the canonical GPv2Settlement
 * address, identical on every chain CoW deploys to. The run reverts if either address is unset or has no
 * code on this chain, so a misconfigured deploy fails loudly rather than caching stale settlement immutables.
 */
contract DeployCowSwapHelper is BaseScript {

    // Canonical CoW Protocol GPv2Settlement, deployed at the same address on every supported chain.
    address constant SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;

    // Upper bound on how far past `block.timestamp` a placed order's `validTo` may reach. Caps the window a
    // stale price can be filled and how long the helper custodies the sell token. Human-tuned per deployment.
    uint256 constant MAX_ORDER_VALIDITY = 1 days;

    function run() public returns (address) {
        return deploy(getConfig());
    }

    function _deploy(ConfigReader.Config memory config) public override broadcast returns (address) {
        require(config.protocolAdmin != address(0), "protocolAdmin must not be zero address");
        require(config.boringVault != address(0), "boringVault must not be zero address");
        require(config.boringVault.code.length != 0, "boringVault must have code");
        require(SETTLEMENT.code.length != 0, "SETTLEMENT has no code on this chain");

        // Permissioned (broadcaster-guarded), no cross-chain protection: same address on every chain.
        bytes32 salt = makeSalt(broadcaster, false, string(abi.encodePacked(config.nameEntropy, ":CowSwapHelper")));

        bytes memory creationCode = type(CowSwapHelper).creationCode;
        address helper = CREATEX.deployCreate3(
            salt,
            abi.encodePacked(
                creationCode, abi.encode(config.protocolAdmin, config.boringVault, SETTLEMENT, MAX_ORDER_VALIDITY)
            )
        );

        console2.log("CowSwapHelper: ", helper);
        return helper;
    }

}
