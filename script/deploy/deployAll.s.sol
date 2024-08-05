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
import { DeployRolesAuthority } from "./single/06_DeployRolesAuthority.s.sol";
import { TellerSetup } from "./single/07_TellerSetup.s.sol";
import { SetAuthorityAndTransferOwnerships } from "./single/08_SetAuthorityAndTransferOwnerships.s.sol";
import { DeployDecoderAndSanitizer } from "./single/09_DeployDecoderAndSanitizer.s.sol";
import {DeployCrossChainARBTellerWithMultiAssetSupportL1} from "./single/05c_L1_DeployCrossChainARBTellerWithMultiAssetSupport.s.sol";
import {DeployCrossChainARBTellerWithMultiAssetSupportL2} from "./single/05c_L2_DeployCrossChainARBTellerWithMultiAssetSupport.s.sol";
import {CrossChainARBTellerWithMultiAssetSupportL1, CrossChainARBTellerWithMultiAssetSupportL2, BridgeData} from "src/base/Roles/CrossChain/CrossChainARBTellerWithMultiAssetSupport.sol";

import { ConfigReader, IAuthority } from "../ConfigReader.s.sol";
import { console } from "forge-std/console.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

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
 * contains chain specific configurations (EX. WETH or BALANCER addresses) that are the same accross all deployments in
 * a chain
 *
 */
contract DeployAll is BaseScript {
    using StdJson for string;

    ConfigReader.Config mainConfig;
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint32 constant DESTINATION_SELECTOR = 11155111;

    function run() public {
        mainConfig = getConfig();

        deploy(mainConfig);
    }

    function deploy(ConfigReader.Config memory config) public override returns (address) {
        // address rateProvider = new DeployRateProviders().deploy(config);
        // config.rateProvider = rateProvider;

        address boringVault = new DeployIonBoringVaultScript().deploy(config);
        config.boringVault = boringVault;

        address manager = new DeployManagerWithMerkleVerification().deploy(config);
        config.manager = manager;

        address accountant = new DeployAccountantWithRateProviders().deploy(config);
        config.accountant = accountant;

        // deploy the teller
        // we use an if statement to determine the teller type and which one to deploy
        config.teller = _deployTeller(config);

        new TellerSetup().deploy(config);

        address rolesAuthority = new DeployRolesAuthority().deploy(config);
        config.rolesAuthority = rolesAuthority;

        new SetAuthorityAndTransferOwnerships().deploy(config);

        new DeployDecoderAndSanitizer().deploy(config);

        // my testing below
        vm.startBroadcast(broadcaster);
        CrossChainARBTellerWithMultiAssetSupportL2 teller = CrossChainARBTellerWithMultiAssetSupportL2(config.teller);
        vm.deal(broadcaster, 100);

        (config.base).call{value:100}("");
        teller.addAsset(ERC20(config.base));
        console.log(ERC20(config.base).balanceOf(broadcaster));
        ERC20(config.base).approve(address(teller.vault()), 1);

        // preform depositAndBridge
        BridgeData memory data = BridgeData({
            chainSelector: DESTINATION_SELECTOR,
            destinationChainReceiver: 0xC2d99d76bb9D46BF8Ec9449E4DfAE48C30CF0839,
            bridgeFeeToken: ERC20(NATIVE),
            messageGas: 80_000,
            data: ""
        });

        uint quote = teller.previewFee(1, data);

        teller.depositAndBridge{value:quote}((ERC20(config.base)), 1, 1, data);
        vm.stopBroadcast();
    }

    function _deployTeller(ConfigReader.Config memory config) public returns (address teller) {
        if (compareStrings(config.tellerContractName, "CrossChainOPTellerWithMultiAssetSupport")) {
            teller = new DeployCrossChainOPTellerWithMultiAssetSupport().deploy(config);
        } else if (compareStrings(config.tellerContractName, "MultiChainLayerZeroTellerWithMultiAssetSupport")) {
            teller = new DeployMultiChainLayerZeroTellerWithMultiAssetSupport().deploy(config);
        } else  if (compareStrings(config.tellerContractName, "CrossChainARBTellerWithMultiAssetSupportL1")){
            teller = new DeployCrossChainARBTellerWithMultiAssetSupportL1().deploy(config);
        }else if (compareStrings(config.tellerContractName, "CrossChainARBTellerWithMultiAssetSupportL2")){
            teller = new DeployCrossChainARBTellerWithMultiAssetSupportL2().deploy(config);
        }else{
            revert INVALID_TELLER_CONTRACT_NAME();
        }
    }

    function compareStrings(string memory a, string memory b) private returns (bool) {
        return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)));
    }
}
