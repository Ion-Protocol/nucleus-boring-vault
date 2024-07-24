// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;
import {console} from "forge-std/Test.sol";
import {BaseScript} from "../../Base.s.sol";
import {MultiChainLayerZeroTellerWithMultiAssetSupport, BridgeData} from "../../../src/base/Roles/CrossChain/MultiChainLayerZeroTellerWithMultiAssetSupport.sol";
import {CrossChainOPTellerWithMultiAssetSupport} from "../../../src/base/Roles/CrossChain/CrossChainOPTellerWithMultiAssetSupport.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

/**
 * @title SendOneWeiCrossChain
 * @author carson@molecularlabs.io
 * @notice This is a utility script just for me to test out the bridging accross chains.
 * It's very messy, and not really meant to be re-ran. But if anyone else is also testing out the LayerZero crosschain and wants a script to 
 * send tokens around this may be of help.
 */
contract SendOneWeiCrossChain is BaseScript {

    address constant SEPOLIA_OPT_LZ_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    uint32 constant SEPOLIA_OPT_EID = 40232;
    uint32 constant SEPOLIA_OPT_CHAIN_ID = 11155420;

    // address constant SEI_DEVNET_LZ_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f; 
    // uint32 constant SEI_DEVNET_SELECTOR = 713715;
    address constant SEPOLIA_MAIN_LZ_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    uint32 constant SEPOLIA_MAIN_EID = 4061;
    uint32 constant SEPOLIA_MAIN_CHAIN_ID = 11155111;


    ERC20 constant WETH_SEPOLIA_MAIN = ERC20(0x5f207d42F869fd1c71d7f0f81a2A67Fc20FF7323);
    ERC20 constant WETH_SEPOLIA_OP = ERC20(0x4200000000000000000000000000000000000006);



    address constant TELLER = 0x8D9d36a33DAD6fb622180b549aB05B6ED71350F7;

    function run() external{

        vm.createSelectFork(vm.rpcUrl("op_sepolia"));
        vm.startBroadcast();
        CrossChainOPTellerWithMultiAssetSupport op = CrossChainOPTellerWithMultiAssetSupport(TELLER);
        // vm.stopBroadcast();


        // vm.createSelectFork(vm.rpcUrl("sepolia_main"));
        // vm.startBroadcast();
        // CrossChainOPTellerWithMultiAssetSupport main = CrossChainOPTellerWithMultiAssetSupport(TELLER);
        // main.setPeer(SEPOLIA_OPT_EID, addressToBytes32(address(main)));
        // main.addChain(SEPOLIA_OPT_EID, true, true, address(main), 100_000);

        // WETH_SEPOLIA_MAIN.approve(address(main.vault()), 1);

        // preform depositAndBridge
        BridgeData memory data = BridgeData({
            chainSelector: SEPOLIA_MAIN_CHAIN_ID,
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
