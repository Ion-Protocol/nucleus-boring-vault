// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AccountantWithRateProviders } from "./../../../src/base/Roles/AccountantWithRateProviders.sol";
import { MultiChainLayerZeroTellerWithMultiAssetSupport } from
    "./../../../src/base/Roles/CrossChain/MultiChainLayerZeroTellerWithMultiAssetSupport.sol";
import { BaseScript } from "./../../Base.s.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { ConfigReader } from "../../ConfigReader.s.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { console2 } from "@forge-std/console2.sol";

contract DeployMultiChainLayerZeroTellerWithMultiAssetSupport is BaseScript {
    using StdJson for string;

    address dead = 0x000000000000000000000000000000000000dEaD;

    struct UlnConfig {
        uint64 confirmations;
        // we store the length of required DVNs and optional DVNs instead of using DVN.length directly to save gas
        uint8 requiredDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
        uint8 optionalDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
        uint8 optionalDVNThreshold; // (0, optionalDVNCount]
        address[] requiredDVNs; // no duplicates. sorted an an ascending order. allowed overlap with optionalDVNs
        address[] optionalDVNs; // no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
    }

    function run() public returns (address teller) {
        return deploy(getConfig());
    }

    function deploy(ConfigReader.Config memory config) public override broadcast returns (address) {
        // Get Config Values

        // Require config Values
        require(config.boringVault.code.length != 0, "boringVault must have code");
        require(config.accountant.code.length != 0, "accountant must have code");
        require(config.tellerSalt != bytes32(0), "tellerSalt");
        require(config.boringVault != address(0), "boringVault");
        require(config.accountant != address(0), "accountant");

        // Create Contract
        bytes memory creationCode = type(MultiChainLayerZeroTellerWithMultiAssetSupport).creationCode;
        MultiChainLayerZeroTellerWithMultiAssetSupport teller = MultiChainLayerZeroTellerWithMultiAssetSupport(
            CREATEX.deployCreate3(
                config.tellerSalt,
                abi.encodePacked(
                    creationCode, abi.encode(broadcaster, config.boringVault, config.accountant, config.lzEndpoint)
                )
            )
        );

        // configure the crosschain functionality, assume same address
        teller.setPeer(config.peerEid, bytes32(bytes20(address(teller))));
        teller.addChain(config.peerEid, true, true, address(teller), config.maxGasForPeer, config.minGasForPeer);

        // Post Deploy Checks
        require(teller.shareLockPeriod() == 0, "share lock period must be zero");
        require(teller.isPaused() == false, "the teller must not be paused");
        require(
            AccountantWithRateProviders(teller.accountant()).vault() == teller.vault(),
            "the accountant vault must be the teller vault"
        );
        require(address(teller.endpoint()) == config.lzEndpoint, "OP Teller must have messenger set");

        _checkUlnConfig(config);
        return address(teller);
    }

    function _checkUlnConfig(ConfigReader.Config memory config) internal {
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(config.lzEndpoint);
        address lib = endpoint.defaultSendLibrary(config.peerEid);
        bytes memory configBytes = endpoint.getConfig(config.teller, lib, config.peerEid, 2);
        UlnConfig memory ulnConfig = abi.decode(configBytes, (UlnConfig));



        uint8 numRequiredDVN = ulnConfig.requiredDVNCount;
        uint8 numOptionalDVN = ulnConfig.optionalDVNCount;
        bool isDead;

        for (uint256 i; i < numRequiredDVN; ++i) {
            if (ulnConfig.requiredDVNs[i] == dead) {
                isDead = true;
            }
        }

        for (uint256 i; i < numRequiredDVN; ++i) {
            if (ulnConfig.optionalDVNs[i] == dead) {
                isDead = true;
            }
        }

        if(!isDead){
            string memory a = vm.prompt("There is a default configuration for this chain/peerEid combination. Would you like to use it? (y/n)");
            if(compareStrings(a,"y")){
                console2.log("using default config");
                return;
            }else{
                console2.log("setting LayerZero ULN config using provided in config file");
                _setConfig(endpoint, lib, config);
            }
        }
    }   

    function _setConfig(ILayerZeroEndpointV2 endpoint, address lib, ConfigReader.Config memory config) internal {

        bytes memory ulnConfigBytes =
            abi.encode(UlnConfig(config.dvnBlockConfirmationsRequired, uint8(config.requiredDnvs.length), uint8(config.optionalDvns.length), config.optionalDvnThreshold, config.requiredDnvs, config.optionalDvns));

        SetConfigParam[] memory setConfigParams = new SetConfigParam[](1);
        setConfigParams[0] = SetConfigParam(config.peerEid, 2, ulnConfigBytes);
        endpoint.setConfig(config.teller, lib, setConfigParams);
    }
}
