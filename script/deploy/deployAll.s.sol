// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseScript } from "./../Base.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

// import {DeployRateProviders} from "./single/01_DeployRateProviders.s.sol";
import { DeployIonBoringVaultScript } from "./single/02_DeployBoringVault.s.sol";
import { DeployManagerWithMerkleVerification } from "./single/03_DeployManagerWithMerkleVerification.s.sol";
import { DeployAccountantWithRateProviders } from "./single/04_DeployAccountantWithRateProviders.s.sol";
import { DeployTellerWithMultiAssetSupport } from "./single/05_DeployTellerWithMultiAssetSupport.s.sol";
import { DeployCrossChainOPTellerWithMultiAssetSupport } from
    "./single/05a_DeployCrossChainOPTellerWithMultiAssetSupport.s.sol";
import { DeployMultiChainLayerZeroTellerWithMultiAssetSupport } from
    "./single/05b_DeployMultiChainLayerZeroTellerWithMultiAssetSupport.s.sol";
import { DeployMultiChainHyperlaneTeller } from "./single/05c_DeployMultiChainHyperlaneTeller.s.sol";
import { DeployRolesAuthority } from "./single/06_DeployRolesAuthority.s.sol";
import { TellerSetup } from "./single/07_TellerSetup.s.sol";
import { SetAuthorityAndTransferOwnerships } from "./single/08_SetAuthorityAndTransferOwnerships.s.sol";

import { ConfigReader, IAuthority } from "../ConfigReader.s.sol";
import { console } from "forge-std/console.sol";

string constant OUTPUT_JSON_PATH = "./deployment-config/out.json";

error INVALID_TELLER_CONTRACT_NAME();

/**
 * @title DeployAll
 * @notice a handy contract to manage deployment of the boring vault system
 * Single Deployments are stored in:
 *      /script/deploy/single
 *
 * each of these are capable of being ran on their own, but this contract will run them all
 *
 * Configurations are stored in:
 *      /deployment-config
 *
 * Contains configuration files that can be specified and customized for deployments
 *
 *      /deployment-config/chain
 *
 * contains chain specific configurations (EX. WETH or BALANCER addresses) that are the same across all deployments in
 * a chain
 *
 */
contract DeployAll is BaseScript {
    using StdJson for string;
    using Strings for address;

    ConfigReader.Config mainConfig;

    // skips the json writing
    function runLiveTest(string memory deployFile) public {
        deploy(ConfigReader.toConfig(vm.readFile(string.concat(CONFIG_PATH_ROOT, deployFile)), getChainConfigFile()));
    }

    function run(string memory deployFile) public {
        deploy(ConfigReader.toConfig(vm.readFile(string.concat(CONFIG_PATH_ROOT, deployFile)), getChainConfigFile()));
        // write everything to an out file
        mainConfig.boringVault.toHexString().write(OUTPUT_JSON_PATH, ".boringVault");
        mainConfig.manager.toHexString().write(OUTPUT_JSON_PATH, ".manager");
        mainConfig.accountant.toHexString().write(OUTPUT_JSON_PATH, ".accountant");
        mainConfig.teller.toHexString().write(OUTPUT_JSON_PATH, ".teller");
        mainConfig.rolesAuthority.toHexString().write(OUTPUT_JSON_PATH, ".rolesAuthority");
    }

    function deploy(ConfigReader.Config memory config) public override returns (address) {
        address boringVault = new DeployIonBoringVaultScript().deploy(config);
        config.boringVault = boringVault;
        console.log("Boring Vault: ", boringVault);

        address manager = new DeployManagerWithMerkleVerification().deploy(config);
        config.manager = manager;
        console.log("Manager: ", manager);

        address accountant = new DeployAccountantWithRateProviders().deploy(config);
        config.accountant = accountant;
        console.log("Accountant: ", accountant);

        // deploy the teller
        // we use an if statement to determine the teller type and which one to deploy
        config.teller = _deployTeller(config);
        console.log("Teller: ", config.teller);

        new TellerSetup().deploy(config);
        console.log("Teller setup complete");

        address rolesAuthority = new DeployRolesAuthority().deploy(config);
        config.rolesAuthority = rolesAuthority;
        console.log("Roles Authority: ", rolesAuthority);

        new SetAuthorityAndTransferOwnerships().deploy(config);
        console.log("Set Authority And Transfer Ownerships Complete");

        mainConfig = config;
    }

    function _deployTeller(ConfigReader.Config memory config) public returns (address teller) {
        if (compareStrings(config.tellerContractName, "CrossChainOPTellerWithMultiAssetSupport")) {
            teller = new DeployCrossChainOPTellerWithMultiAssetSupport().deploy(config);
        } else if (compareStrings(config.tellerContractName, "MultiChainLayerZeroTellerWithMultiAssetSupport")) {
            teller = new DeployMultiChainLayerZeroTellerWithMultiAssetSupport().deploy(config);
        } else if (compareStrings(config.tellerContractName, "MultiChainHyperlaneTellerWithMultiAssetSupport")) {
            teller = new DeployMultiChainHyperlaneTeller().deploy(config);
        } else if (compareStrings(config.tellerContractName, "TellerWithMultiAssetSupport")) {
            teller = new DeployTellerWithMultiAssetSupport().deploy(config);
        } else {
            revert INVALID_TELLER_CONTRACT_NAME();
        }
    }
}
