// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {IRateProvider} from "./../../../src/interfaces/IRateProvider.sol";
import {EthPerWstEthRateProvider} from "./../../../src/oracles/EthPerWstEthRateProvider.sol";

import {BaseScript} from "./../Base.s.sol";
import {stdJson as StdJson} from "@forge-std/StdJson.sol";
import {ConfigReader} from "../ConfigReader.s.sol";
import {console} from "@forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {EthPerTokenRateProvider, IPriceFeed} from "src/oracles/EthPerTokenRateProvider.sol";

/// NOTE This script must change based on the supported assets of each vault deployment.
contract DeployRateProviders is BaseScript {
    using StdJson for string;
    using Strings for address;

    function run() public {
        string memory config = requestConfigFileFromUser();
        string memory chainConfig = getChainConfigFile();

        address[] memory assets = config.readAddressArray(".teller.assets");
        uint maxTimeFromLastUpdate = config.readUint(".rateProvider.maxTimeFromLastUpdate");

        for(uint i; i < assets.length; ++i){
            require(assets[i].code.length > 0, "asset must have code");
            string memory rateProviderKey = string(abi.encodePacked(".assetToRateProviderAndPriceFeed.",assets[i].toHexString(),".rateProvider"));
            address rateProvider  = chainConfig.readAddress(rateProviderKey);
            // must deploy new rate provider and set the value
            if(rateProvider == address(0)){
                address priceFeed  = chainConfig.readAddress(string(abi.encodePacked(".assetToRateProviderAndPriceFeed.",assets[i].toHexString(),".priceFeed")));
                // TODO remove this hardcoded 18, and replace it with either config value OR something constant
                // review with Jun/Jamie
                rateProvider = deployRateProvider(priceFeed, maxTimeFromLastUpdate, 18);
                string memory chainConfigFilePath = string.concat(
                    CONFIG_CHAIN_ROOT,
                    Strings.toString(block.chainid),
                    ".json"
                );
                rateProvider.toHexString().write(chainConfigFilePath, rateProviderKey);
            }
        }
    }

    function deploy(ConfigReader.Config memory config) public override broadcast returns(address){}

    function deployRateProvider(address priceFeed, uint maxTimeFromLastUpdate, uint8 decimals) public broadcast returns(address){
        require(maxTimeFromLastUpdate > 0, "max time from last update = 0");
        require(priceFeed.code.length > 0, "price feed must have code");

        // removed the salt...
        // should this be CREATEX'd?
        // or should we just avoid deterministic deployments here?
        // leaning on that, but todo is confirm with team and remove salt if so
        EthPerTokenRateProvider rateProvider = new EthPerTokenRateProvider(
            IPriceFeed(priceFeed), maxTimeFromLastUpdate, decimals
        );

        return address(rateProvider);
    }
}
