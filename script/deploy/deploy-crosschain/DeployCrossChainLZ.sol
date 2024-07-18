// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {DeployCrossChainBase, CrossChainLayerZeroTellerWithMultiAssetSupport} from "./DeployCrossChainBase.s.sol";
import {console} from "forge-std/Test.sol";
// import {console2} from "";
contract DeployCrossChainLZ is DeployCrossChainBase {

    address constant SEPOLIA_OPT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    uint32 constant SEPOLIA_OPT_EID = 40232;

    // address constant SEI_DEVNET = 0x6EDCE65403992e310A62460808c4b910D972f10f; 
    // uint32 constant SEI_DEVNET_SELECTOR = 713715;

    address constant SEPOLIA_MAIN = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    uint32 constant SEPOLIA_MAIN_EID = 40161;

    function run() external{
        addressesByRpc["sepolia_main"]["WETH"] = 0x5f207d42F869fd1c71d7f0f81a2A67Fc20FF7323;
        addressesByRpc["op_sepolia"]["WETH"] = 0x4200000000000000000000000000000000000006;


        // address opTellerAddress = CREATEX.deployCreate2(salt, initCode);
        vm.createSelectFork(vm.rpcUrl("sepolia_main"));
        vm.startBroadcast();
        CrossChainLayerZeroTellerWithMultiAssetSupport main = fullDeployForChainLZ("sepolia_main", SEPOLIA_MAIN);
        // we use the main address here, because main and op actually will be deployed with the same address
        // this needs to be done here, and not later because foundry will wipe the state when broadcast is stopped.
        main.setPeer(SEPOLIA_OPT_EID, addressToBytes32(address(main)));
        main.addChain(SEPOLIA_OPT_EID, true, true, address(main), 100_000, 0);

        vm.stopBroadcast();

        vm.createSelectFork(vm.rpcUrl("op_sepolia"));
        vm.startBroadcast();
        CrossChainLayerZeroTellerWithMultiAssetSupport op = fullDeployForChainLZ("op_sepolia", SEPOLIA_OPT);
        op.setPeer(SEPOLIA_MAIN_EID, addressToBytes32(address(main)));
        op.addChain(SEPOLIA_MAIN_EID, true, true, address(main), 100_000, 0);
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
