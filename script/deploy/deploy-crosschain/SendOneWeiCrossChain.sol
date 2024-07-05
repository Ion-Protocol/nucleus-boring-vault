// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;
import {console} from "forge-std/Test.sol";
import {BaseScript} from "../../Base.s.sol";
import {CrossChainLayerZeroTellerWithMultiAssetSupport, BridgeData} from "../../../src/base/Roles/CrossChain/CrossChainLayerZeroTellerWithMultiAssetSupport.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

/**
 * @title SendOneWeiCrossChain
 * @author carson@molecularlabs.io
 * @notice This is a utility script just for me to test out the bridging accross chains.
 * It's very messy, and not really meant to be re-ran. But if anyone else is also testing out the LayerZero crosschain and wants a script to 
 * send tokens around this is on that does it.
 */
contract SendOneWeiCrossChain is BaseScript {

    address constant SEPOLIA_OPT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    uint32 constant SEPOLIA_OPT_EID = 40232;

    // address constant SEI_DEVNET = 0x6EDCE65403992e310A62460808c4b910D972f10f; 
    // uint32 constant SEI_DEVNET_SELECTOR = 713715;

    address constant SEPOLIA_MAIN = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    uint32 constant SEPOLIA_MAIN_EID = 4061;

    ERC20 constant WETH_SEPOLIA_MAIN = ERC20(0x5f207d42F869fd1c71d7f0f81a2A67Fc20FF7323);
    ERC20 constant WETH_SEPOLIA_OP = ERC20(0x4200000000000000000000000000000000000006);

    address constant TELLER = 0xfFEa4FB47AC7FA102648770304605920CE35660c;

    function run() external{

        vm.createSelectFork(vm.rpcUrl("op_sepolia"));
        vm.startBroadcast();
        CrossChainLayerZeroTellerWithMultiAssetSupport op = CrossChainLayerZeroTellerWithMultiAssetSupport(TELLER);
        // // we use the main address here, because main and op actually will be deployed with the same address
        // // this needs to be done here, and not later because foundry will wipe the state when broadcast is stopped.
        op.setPeer(SEPOLIA_MAIN_EID, addressToBytes32(TELLER));
        op.addChain(SEPOLIA_MAIN_EID, true, true, TELLER, 100_000);
        // vm.stopBroadcast();


        // vm.createSelectFork(vm.rpcUrl("sepolia_main"));
        // vm.startBroadcast();
        // CrossChainLayerZeroTellerWithMultiAssetSupport main = CrossChainLayerZeroTellerWithMultiAssetSupport(TELLER);
        // main.setPeer(SEPOLIA_OPT_EID, addressToBytes32(address(main)));
        // main.addChain(SEPOLIA_OPT_EID, true, true, address(main), 100_000);

        // WETH_SEPOLIA_MAIN.approve(address(main.vault()), 1);

        // preform depositAndBridge
        BridgeData memory data = BridgeData({
            chainSelector: SEPOLIA_MAIN_EID,
            destinationChainReceiver: broadcaster,
            bridgeFeeToken: (WETH_SEPOLIA_OP),
            messageGas: 80_000,
            data: ""
        });

        uint quote = op.previewFee(1, data);
        // main.depositAndBridge{value:quote}((WETH_SEPOLIA_MAIN), 1, 1, data);
        op.bridge{value:quote}(1, data);

        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
