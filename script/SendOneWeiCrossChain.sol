// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19 <=0.9.0;

import {ICreateX} from "./../src/interfaces/ICreateX.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Script, stdJson} from "@forge-std/Script.sol";
import {console2} from "@forge-std/console2.sol";

import {ConfigReader, IAuthority} from "./ConfigReader.s.sol";
import {console} from "forge-std/Test.sol";
import {CrossChainARBTellerWithMultiAssetSupportL1, BridgeData} from "src/base/Roles/CrossChain/CrossChainARBTellerWithMultiAssetSupport.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

contract SendOneWeiCrossChain is Script {
    address constant SOURCE_TELLER = 0x11683E12e0BEbFcc0a47151C5C8d79457a4d6AC6;
    uint32 constant DESTINATION_SELECTOR = 421614;
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ERC20 constant WETH_SEPOLIA = ERC20(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);

    function run() external{
        address from = vm.envOr({name: "ETH_FROM", defaultValue: address(0)});
        vm.startBroadcast(from);
        CrossChainARBTellerWithMultiAssetSupportL1 teller = CrossChainARBTellerWithMultiAssetSupportL1(SOURCE_TELLER);
        
        teller.addAsset(WETH_SEPOLIA);
        WETH_SEPOLIA.approve(address(teller.vault()), 1);

        // preform depositAndBridge
        BridgeData memory data = BridgeData({
            chainSelector: DESTINATION_SELECTOR,
            destinationChainReceiver: 0xC2d99d76bb9D46BF8Ec9449E4DfAE48C30CF0839,
            bridgeFeeToken: ERC20(NATIVE),
            messageGas: 80_000,
            data: ""
        });

        uint quote = teller.previewFee(1, data);

        teller.depositAndBridge{value:quote}((WETH_SEPOLIA), 1, 1, data);
        vm.stopBroadcast();
    }
}
