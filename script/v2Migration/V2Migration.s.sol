// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseScript } from "script/Base.s.sol";
import { console } from "forge-std/console.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { RateProviderConfig } from "./../../../src/base/Roles/RateProviderConfig.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import { V1Accountant } from "script/v2Migration/IV1Accountant.sol";
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
import { AccountantWithRateProviders } from "./../../../src/base/Roles/AccountantWithRateProviders.sol";

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

    RateProviderConfig constant rateProviderConfig = RateProviderConfig(0xB11d016874eED24697F2655c3Ce6Ef53b302E36A);
    address constant managerWithTokenBalanceVerification = 0x4940fC530aCE70B070e38469D3f75D801f0180A5;
    address constant pauser = 0x858d3eE2a16F7B6E43C8D87a5E1F595dE32f4419;

    ConfigReader.Config mainConfig;

    function run(string memory deployFile) public {
        deploy(ConfigReader.toConfig(vm.readFile(string.concat(CONFIG_PATH_ROOT, deployFile)), getChainConfigFile()));

        // write everything to an out file
        mainConfig.manager.toHexString().write(OUTPUT_JSON_PATH, ".v2Manager");
        mainConfig.accountant.toHexString().write(OUTPUT_JSON_PATH, ".v2Accountant");
        mainConfig.teller.toHexString().write(OUTPUT_JSON_PATH, ".v2Teller");
        mainConfig.rolesAuthority.toHexString().write(OUTPUT_JSON_PATH, ".v2RolesAuthority");
    }

    function _checkAssets(ConfigReader.Config memory config) internal {
        bool failures;
        string memory errString = "\x1b[33mWARNING\x1b[0m";
        ERC20 base = ERC20(config.base);

        for (uint256 i; i < config.assets.length; ++i) {
            ERC20 quote = ERC20(config.assets[i]);
            if (rateProviderConfig.getLength(base, quote) == 0) {
                errString = string.concat(
                    errString,
                    " Rate Providers Not configured for Base: ",
                    vm.toString(config.base),
                    "| Quote: ",
                    vm.toString(config.assets[i]),
                    "\n"
                );
                failures = true;
            }
        }
        if (failures) {
            vm.prompt(
                string.concat(errString, "Some rate provider data was not found. Press ENTER to continue anyways")
            );
        }
    }

    function deploy(ConfigReader.Config memory config) public override returns (address) {
        _checkAssets(config);
        address manager = new DeployManagerWithMerkleVerification().deploy(config);
        config.manager = manager;
        console.log("Manager: ", manager);

        string memory json = vm.readFile(OUTPUT_JSON_PATH);
        address v1Accountant = json.readAddress(".v1Accountant");
        (,,, uint256 exchangeRate,,,,,,) = V1Accountant(v1Accountant).accountantState();

        address accountant = new DeployAccountantWithRateProviders().deploy(config, exchangeRate);
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
