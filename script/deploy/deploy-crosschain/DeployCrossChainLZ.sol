// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {DeployCrossChainBase, CrossChainLayerZeroTellerWithMultiAssetSupport} from "./DeployCrossChainLZBase.sol";

contract DeployRateProviders is DeployCrossChainBase {

    address constant SEPOLIA_OPT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    uint32 constant SEPOLIA_OPT_SELECTOR = 11155420;

    // address constant SEI_DEVNET = 0x6EDCE65403992e310A62460808c4b910D972f10f; 
    // uint32 constant SEI_DEVNET_SELECTOR = 713715;

    address constant SEPOLIA_MAIN = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    uint32 constant SEPOLIA_MAIN_SELECTOR = 11155111;

    function run() external{
        CrossChainLayerZeroTellerWithMultiAssetSupport main = fullDeployForChain("sepolia_main", SEPOLIA_MAIN);
        CrossChainLayerZeroTellerWithMultiAssetSupport op = fullDeployForChain("op_sepolia", SEPOLIA_OPT);

        // broadcast and fork
        vm.startBroadcast(broadcaster);
        vm.rpcUrl("sepolia_main");
        main.setPeer(SEPOLIA_OPT_SELECTOR, addressToBytes32(address(op)));
        vm.stopBroadcast();

        vm.startBroadcast(broadcaster);
        vm.rpcUrl("op_sepolia");
        op.setPeer(SEPOLIA_MAIN_SELECTOR, addressToBytes32(address(main)));
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
