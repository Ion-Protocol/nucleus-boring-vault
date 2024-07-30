// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {IRateProvider} from "./../../../src/interfaces/IRateProvider.sol";
import {EthPerWstEthRateProvider} from "./../../../src/oracles/EthPerWstEthRateProvider.sol";

import {ETH_PER_STETH_CHAINLINK, WSTETH_ADDRESS} from "@ion-protocol/Constants.sol";

import {BaseScript} from "./../Base.s.sol";
import {stdJson as StdJson} from "@forge-std/StdJson.sol";
import {ConfigReader} from "../ConfigReader.s.sol";
import {console} from "@forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// NOTE This script must change based on the supported assets of each vault deployment.
contract DeployRateProviders is BaseScript {
    using StdJson for string;
    using Strings for address;

    function run() public {
        string memory config = requestConfigFileFromUser();
        string memory chainConfig = getChainConfigFile();

        address[] memory assets = config.readAddressArray(".teller.assets");
        for(uint i; i < assets.length; ++i){
            address rateProvider  = chainConfig.readAddress(string(abi.encodePacked(".assetToRateProviderAndPriceFeed.",assets[i].toHexString(),".rateProvider")));
            // must deploy new rate provider and set the value
            if(rateProvider == address(0)){
                address priceFeed  = chainConfig.readAddress(string(abi.encodePacked(".assetToRateProviderAndPriceFeed.",assets[i].toHexString(),".priceFeed")));

            }
        }
    }

    function deploy(ConfigReader.Config memory config) public override broadcast returns(address){}

    function deployRateProvider(ConfigReader.Config memory config) public broadcast returns(address){

        EthPerWstEthRateProvider rateProvider = new EthPerWstEthRateProvider{salt: config.rateProviderSalt}(
            address(ETH_PER_STETH_CHAINLINK), address(WSTETH_ADDRESS), config.maxTimeFromLastUpdate
        );

        for(uint i; i < config.assets.length; ++i){
            address asset = config.assets[0];
        }
        // Create Contract


        return address(rateProvider);
    }
}
