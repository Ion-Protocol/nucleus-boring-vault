// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseScript } from "script/Base.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { DeployIonBoringVaultScript } from "script/deploy/single/02_DeployBoringVault.s.sol";
import { DeployManagerWithMerkleVerification } from "script/deploy/single/03_DeployManagerWithMerkleVerification.s.sol";
import { DeployAccountantWithRateProviders } from "script/deploy/single/04_DeployAccountantWithRateProviders.s.sol";
import { DeployTellerWithMultiAssetSupport } from "script/deploy/single/05_DeployTellerWithMultiAssetSupport.s.sol";
import { DeployMultiChainLayerZeroTellerWithMultiAssetSupport } from
    "script/deploy/single/05b_DeployMultiChainLayerZeroTellerWithMultiAssetSupport.s.sol";
import { DeployMultiChainHyperlaneTeller } from "script/deploy/single/05c_DeployMultiChainHyperlaneTeller.s.sol";
import { DeployRolesAuthority } from "script/deploy/single/06_DeployRolesAuthority.s.sol";
import { TellerSetup } from "script/deploy/single/07_TellerSetup.s.sol";
import { SetAuthorityAndTransferOwnerships } from "script/deploy/single/08_SetAuthorityAndTransferOwnerships.s.sol";

import { ConfigReader, IAuthority } from "../ConfigReader.s.sol";
import { console } from "forge-std/console.sol";

string constant OUTPUT_JSON_PATH = "script/v2Migration/out.json";

error INVALID_TELLER_CONTRACT_NAME();

/**
 * @title V2Migration
 * @notice Works very similar to deployAll in regards to V2 deployment
 *  but excludes boringVault
 */
contract V2Migration is BaseScript {
    using StdJson for string;
    using Strings for address;

    ConfigReader.Config mainConfig;

    function run(string memory deployFile) public {
        deploy(ConfigReader.toConfig(vm.readFile(string.concat(CONFIG_PATH_ROOT, deployFile)), getChainConfigFile()));

        // write everything to an out file
        mainConfig.manager.toHexString().write(OUTPUT_JSON_PATH, ".v2Manager");
        mainConfig.accountant.toHexString().write(OUTPUT_JSON_PATH, ".v2Accountant");
        mainConfig.teller.toHexString().write(OUTPUT_JSON_PATH, ".v2Teller");
        mainConfig.rolesAuthority.toHexString().write(OUTPUT_JSON_PATH, ".v2RolesAuthority");
    }

    function deploy(ConfigReader.Config memory config) public override returns (address) {
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
        if (compareStrings(config.tellerContractName, "MultiChainLayerZeroTellerWithMultiAssetSupport")) {
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
