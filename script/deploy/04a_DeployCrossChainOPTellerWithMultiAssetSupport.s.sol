// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {AccountantWithRateProviders} from "./../../src/base/Roles/AccountantWithRateProviders.sol";
import {CrossChainOPTellerWithMultiAssetSupport} from "./../../src/base/Roles/CrossChain/CrossChainOPTellerWithMultiAssetSupport.sol";
import {BaseScript} from "./../Base.s.sol";
import {stdJson as StdJson} from "@forge-std/StdJson.sol";

contract DeployCrossChainOPTellerWithMultiAssetSupport is BaseScript {
    using StdJson for string;

    string path = "./deployment-config/04a_DeployCrossChainOPTellerWithMultiAssetSupport.json";
    string config = vm.readFile(path);

    bytes32 tellerSalt = config.readBytes32(".tellerSalt");
    address boringVault = config.readAddress(".boringVault");
    address accountant = config.readAddress(".accountant");
    address messenger = config.readAddress(".messenger");
    address weth = config.readAddress(".weth");
    uint256 maxGasForPeer = config.readUint(".maxGasForPeer");
    uint256 minGasForPeer = config.readUint(".minGasForPeer");

    function run() public broadcast returns (CrossChainOPTellerWithMultiAssetSupport teller) {
        require(boringVault.code.length != 0, "boringVault must have code");
        require(accountant.code.length != 0, "accountant must have code");
        
        require(tellerSalt != bytes32(0), "tellerSalt");
        require(boringVault != address(0), "boringVault");
        require(accountant != address(0), "accountant");

        bytes memory creationCode = type(CrossChainOPTellerWithMultiAssetSupport).creationCode;

        teller = CrossChainOPTellerWithMultiAssetSupport(
            CREATEX.deployCreate3(
                tellerSalt,
                abi.encodePacked(creationCode, abi.encode(broadcaster, boringVault, accountant, weth, messenger))
            )
        );

        // configure the crosschain functionality
        teller.setGasBounds(uint32(minGasForPeer), uint32(maxGasForPeer));

        require(teller.shareLockPeriod() == 0, "share lock period must be zero");
        require(teller.isPaused() == false, "the teller must not be paused");
        require(
            AccountantWithRateProviders(teller.accountant()).vault() == teller.vault(),
            "the accountant vault must be the teller vault"
        );
        require(address(teller.messenger()) == messenger, "OP Teller must have messenger set");
    }
}
