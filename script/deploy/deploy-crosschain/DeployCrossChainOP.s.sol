// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {DeployCrossChainBase, CrossChainOPTellerWithMultiAssetSupport} from "./DeployCrossChainBase.s.sol";
import {console} from "forge-std/Test.sol";
// import {console2} from "";
contract DeployCrossChainOP is DeployCrossChainBase {

    address constant SEPOLIA_OPT_MESSENGER = 0x4200000000000000000000000000000000000007;
    uint32 constant SEPOLIA_OPT_CHAIN_ID = 11155420;

    // address constant SEI_DEVNET = 0x6EDCE65403992e310A62460808c4b910D972f10f; 
    // uint32 constant SEI_DEVNET_SELECTOR = 713715;

    address constant SEPOLIA_MAIN_MESSENGER = 0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef;
    uint32 constant SEPOLIA_MAIN_CHAIN_ID = 11155111;

    function run() external{
        addressesByRpc["sepolia_main"]["WETH"] = 0x5f207d42F869fd1c71d7f0f81a2A67Fc20FF7323;
        addressesByRpc["op_sepolia"]["WETH"] = 0x4200000000000000000000000000000000000006;


        // address opTellerAddress = CREATEX.deployCreate2(salt, initCode);
        vm.createSelectFork(vm.rpcUrl("sepolia_main"));
        vm.startBroadcast();
        CrossChainOPTellerWithMultiAssetSupport main = fullDeployForChainOP("sepolia_main", SEPOLIA_MAIN_MESSENGER);
        // we use the main address here, because main and op actually will be deployed with the same address
        // this needs to be done here, and not later because foundry will wipe the state when broadcast is stopped.
        main.addChain(SEPOLIA_OPT_CHAIN_ID, true, true, address(main), 100_000, 0);

        vm.stopBroadcast();

        vm.createSelectFork(vm.rpcUrl("op_sepolia"));
        vm.startBroadcast();
        CrossChainOPTellerWithMultiAssetSupport op = fullDeployForChainOP("op_sepolia", SEPOLIA_OPT_MESSENGER);
        op.addChain(SEPOLIA_MAIN_CHAIN_ID, true, true, address(main), 100_000, 0);
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
