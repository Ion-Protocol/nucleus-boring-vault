// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseScript } from "./../../Base.s.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { ConfigReader, IAuthority } from "../../ConfigReader.s.sol";
import { AuthOwnable2Step } from "src/helper/AuthOwnable2Step.sol";
/**
 * Update `rolesAuthority` and transfer ownership from deployer EOA to the
 * protocol.
 */
contract SetAuthorityAndTransferOwnerships is BaseScript {
    using StdJson for string;

    function run() public {
        deploy(getConfig());
    }

    function deploy(ConfigReader.Config memory config) public override broadcast returns (address) {
        // Require config Values
        require(address(config.boringVault).code.length != 0, "boringVault must have code");
        require(address(config.manager).code.length != 0, "manager must have code");
        require(address(config.teller).code.length != 0, "teller must have code");
        require(address(config.accountant).code.length != 0, "accountant must have code");
        require(address(config.boringVault) != address(0), "boringVault");
        require(address(config.manager) != address(0), "manager");
        require(address(config.accountant) != address(0), "accountant");
        require(address(config.teller) != address(0), "teller");
        require(config.rolesAuthority != address(0), "rolesAuthority");
        require(config.protocolAdmin != address(0), "protocolAdmin");

        // Set Authority
        IAuthority(config.boringVault).setAuthority(config.rolesAuthority);
        IAuthority(config.accountant).setAuthority(config.rolesAuthority);
        IAuthority(config.manager).setAuthority(config.rolesAuthority);
        IAuthority(config.teller).setAuthority(config.rolesAuthority);
        IAuthority(config.boringVault).transferOwnership(config.protocolAdmin);
        IAuthority(config.manager).transferOwnership(config.protocolAdmin);
        IAuthority(config.accountant).transferOwnership(config.protocolAdmin);
        IAuthority(config.teller).transferOwnership(config.protocolAdmin);
        IAuthority(config.rolesAuthority).transferOwnership(config.protocolAdmin);

        // Post Configuration Check
        require(AuthOwnable2Step(config.boringVault).pendingOwner() == config.protocolAdmin, "boringVault");
        require(AuthOwnable2Step(config.manager).pendingOwner() == config.protocolAdmin, "manager");
        require(AuthOwnable2Step(config.accountant).pendingOwner() == config.protocolAdmin, "accountant");
        require(AuthOwnable2Step(config.teller).pendingOwner() == config.protocolAdmin, "teller");
    }
}
