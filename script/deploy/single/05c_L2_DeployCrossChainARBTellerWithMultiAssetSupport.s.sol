// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {BaseScript} from "../../Base.s.sol";
import {CrossChainARBTellerWithMultiAssetSupportL2} from "src/base/Roles/CrossChain/CrossChainARBTellerWithMultiAssetSupport.sol";
import {console} from "forge-std/Test.sol";
import {ConfigReader} from "../../ConfigReader.s.sol";
import {AccountantWithRateProviders} from "./../../../src/base/Roles/AccountantWithRateProviders.sol";

contract DeployCrossChainARBTellerWithMultiAssetSupportL2 is BaseScript {

    function run() external returns(address){
        return deploy(getConfig());
    }

    function deploy(ConfigReader.Config memory config) public broadcast override returns(address){
        // Require config Values
        require(config.boringVault.code.length != 0, "boringVault must have code");
        require(config.accountant.code.length != 0, "accountant must have code");
        require(config.tellerSalt != bytes32(0), "tellerSalt");
        require(config.boringVault != address(0), "boringVault");
        require(config.accountant != address(0), "accountant");

        // Create Contract
        bytes memory creationCode = type(CrossChainARBTellerWithMultiAssetSupportL2).creationCode;
        CrossChainARBTellerWithMultiAssetSupportL2 teller = CrossChainARBTellerWithMultiAssetSupportL2(
            CREATEX.deployCreate3(
                config.tellerSalt,
                abi.encodePacked(creationCode, abi.encode(broadcaster, config.boringVault, config.accountant))
            )
        );

        // configure the crosschain functionality
        require(teller.owner() == broadcaster, "teller owner must be broadcaster");
        teller.setGasBounds(uint32(config.minGasForPeer), uint32(config.maxGasForPeer));

        // Post Deploy Checks
        require(teller.shareLockPeriod() == 0, "share lock period must be zero");
        require(teller.isPaused() == false, "the teller must not be paused");
        require(
            AccountantWithRateProviders(teller.accountant()).vault() == teller.vault(),
            "the accountant vault must be the teller vault"
        );

        return address(teller);
    }

}
