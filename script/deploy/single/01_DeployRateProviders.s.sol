// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {IRateProvider} from "./../../../src/interfaces/IRateProvider.sol";
import {EthPerWstEthRateProvider} from "./../../../src/oracles/EthPerWstEthRateProvider.sol";

import {ETH_PER_STETH_CHAINLINK, WSTETH_ADDRESS} from "@ion-protocol/Constants.sol";

import {BaseScript} from "./../../Base.s.sol";
import {stdJson as StdJson} from "@forge-std/StdJson.sol";
import {ConfigReader} from "../../ConfigReader.s.sol";

/// NOTE This script must change based on the supported assets of each vault deployment.
contract DeployRateProviders is BaseScript {
    using StdJson for string;

    function run() public returns (address rateProvider) {
        return deploy(getConfig());
    }

    function deploy(ConfigReader.Config memory config) public override broadcast returns(address){
        // Create Contract
        EthPerWstEthRateProvider rateProvider = new EthPerWstEthRateProvider(
            address(ETH_PER_STETH_CHAINLINK), address(WSTETH_ADDRESS), config.maxTimeFromLastUpdate
        );

        return address(rateProvider);
    }
}
