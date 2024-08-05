// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19 <=0.9.0;

import {Script, stdJson} from "@forge-std/Script.sol";
import {console2} from "@forge-std/console2.sol";
import {console} from "forge-std/Test.sol";
import {CrossChainARBTellerWithMultiAssetSupportL1, BridgeData, AddressAliasHelper} from "src/base/Roles/CrossChain/CrossChainARBTellerWithMultiAssetSupport.sol";

contract GetL2AliasAddress is Script {
    function run() external{
        address from = 0x323AC292847fa5E4Eadc053631e9817B2532e9Fa;

        address l2Alias = AddressAliasHelper.applyL1ToL2Alias(from);
        console.log("address: ",from);
        console.log("alias: ",l2Alias);
    }
}