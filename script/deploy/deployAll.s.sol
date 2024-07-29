// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {BaseScript} from "./../Base.s.sol";
import {console} from "forge-std/console.sol";
import {stdJson as StdJson} from "@forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {DeployIonBoringVaultScript} from "./single/01_DeployBoringVault.s.sol";
import {DeployManagerWithMerkleVerification} from "./single/02_DeployManagerWithMerkleVerification.s.sol";
import {DeployAccountantWithRateProviders} from "./single/03_DeployAccountantWithRateProviders.s.sol";
import {DeployTellerWithMultiAssetSupport} from "./single/04_DeployTellerWithMultiAssetSupport.s.sol";
import {DeployCrossChainOPTellerWithMultiAssetSupport} from "./single/04a_DeployCrossChainOPTellerWithMultiAssetSupport.s.sol";
import {DeployMultiChainLayerZeroTellerWithMultiAssetSupport} from "./single/04b_DeployMultiChainLayerZeroTellerWithMultiAssetSupport.s.sol";
import {DeployRolesAuthority} from "./single/05_DeployRolesAuthority.s.sol";
import {SetAuthorityAndTransferOwnerships} from "./single/06_SetAuthorityAndTransferOwnerships.s.sol";
import {DeployDecoderAndSanitizer} from "./single/07_DeployDecoderAndSanitizer.s.sol";
import {DeployRateProviders} from "./single/08_DeployRateProviders.s.sol";
import {DeployCrossChainARBTellerWithMultiAssetSupportL1} from "./single/04c_L1_DeployCrossChainARBTellerWithMultiAssetSupport.s.sol";
import {DeployCrossChainARBTellerWithMultiAssetSupportL2} from "./single/04c_L2_DeployCrossChainARBTellerWithMultiAssetSupport.s.sol";

import {ConfigReader, IAuthority} from "../ConfigReader.s.sol";
import {console} from "forge-std/console.sol";

string constant OUTPUT_JSON_PATH = "/deployment-config/out.json";
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
 * contains chain specific configurations (EX. WETH or BALANCER addresses) that are the same accross all deployments in a chain
 * 
 */
contract DeployAll is BaseScript{
    using StdJson for string;

    ConfigReader.Config mainConfig;

    function run() public{
        mainConfig = getConfig();

        deploy(mainConfig);
    }

    function deploy(ConfigReader.Config memory config) public override returns(address){
        address boringVault = new DeployIonBoringVaultScript().deploy(config);
        config.boringVault = boringVault;

        address manager = new DeployManagerWithMerkleVerification().deploy(config);
        config.manager = manager;

        address accountant = new DeployAccountantWithRateProviders().deploy(config);
        config.accountant = accountant;

        // deploy the teller
        // we use an if statement to determine the teller type and which one to deploy
        config.teller = _deployTeller(config);

        address rolesAuthority = new DeployRolesAuthority().deploy(config);
        config.rolesAuthority = rolesAuthority;

        new SetAuthorityAndTransferOwnerships().deploy(config);

        new DeployDecoderAndSanitizer().deploy(config);
        
        new DeployRateProviders().deploy(config);

    }

    function _deployTeller(ConfigReader.Config memory config) public returns(address teller){
        if(compareStrings(config.tellerContractName,"CrossChainOPTellerWithMultiAssetSupport")){
            teller = new DeployCrossChainOPTellerWithMultiAssetSupport().deploy(config);
        }else if (compareStrings(config.tellerContractName, "MultiChainLayerZeroTellerWithMultiAssetSupport")){
            teller = new DeployMultiChainLayerZeroTellerWithMultiAssetSupport().deploy(config);
        }else if (compareStrings(config.tellerContractName, "CrossChainARBTellerWithMultiAssetSupportL1")){
            teller = new DeployCrossChainARBTellerWithMultiAssetSupportL1().deploy(config);
        }else if(compareStrings(config.tellerContractName, "CrossChainARBTellerWithMultiAssetSupportL2")){
            teller = new DeployCrossChainARBTellerWithMultiAssetSupportL2().deploy(config);
        }else{
            revert INVALID_TELLER_CONTRACT_NAME();
        }
    }

    function compareStrings(string memory a, string memory b) private returns(bool){
        return(
            keccak256(abi.encodePacked(a))
            ==
            keccak256(abi.encodePacked(b))
        );
    }
}