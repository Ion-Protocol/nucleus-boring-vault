// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19 <=0.9.0;

import {ICreateX} from "./../src/interfaces/ICreateX.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Script, stdJson} from "@forge-std/Script.sol";
import {console2} from "@forge-std/console2.sol";

import {ConfigReader, IAuthority} from "./ConfigReader.s.sol";
import {console} from "forge-std/Test.sol";
import {CrossChainARBTellerWithMultiAssetSupportL1, CrossChainARBTellerWithMultiAssetSupportL2, BridgeData} from "src/base/Roles/CrossChain/CrossChainARBTellerWithMultiAssetSupport.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {ArbSys} from "@arbitrum/nitro-contracts/precompiles/ArbSys.sol";

ArbSys constant ARBSYS = ArbSys(0x000000000000000000000000000000000000006E);

contract ArbSysMock {
    function sendTxToL1(address _l1Target, bytes memory _data) external payable returns (uint256) {
        return 0;
    }
}

contract SendOneWeiCrossChain is Script {
    address constant SOURCE_TELLER = 0x3cCbd685C109c31eE65EDe85bd03932511F4B5E9;
    uint32 constant DESTINATION_SELECTOR = 11155111;
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ERC20 constant WETH_SEPOLIA = ERC20(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);
    ERC20 constant WETH_ARB = ERC20(0x980B62Da83eFf3D4576C647993b0c1D7faf17c73);
    function run() external{

        address from = vm.envOr({name: "ETH_FROM", defaultValue: address(0)});
        vm.startBroadcast(from);
        // (bool success, bytes memory d) = address(ARBSYS).call(abi.encodeWithSelector(ARBSYS.arbOSVersion.selector));
        // console.logBytes(d); 
        ArbSysMock xX = new ArbSysMock();
        vm.etch(address(ARBSYS), address(xX).code);

        CrossChainARBTellerWithMultiAssetSupportL2 teller = CrossChainARBTellerWithMultiAssetSupportL2(SOURCE_TELLER);
        
        teller.addAsset(WETH_ARB);
        WETH_ARB.approve(address(teller.vault()), 1);

        // preform depositAndBridge
        BridgeData memory data = BridgeData({
            chainSelector: DESTINATION_SELECTOR,
            destinationChainReceiver: 0xC2d99d76bb9D46BF8Ec9449E4DfAE48C30CF0839,
            bridgeFeeToken: ERC20(NATIVE),
            messageGas: 80_000,
            data: ""
        });

        uint quote = teller.previewFee(1, data);

        teller.depositAndBridge{value:quote}((WETH_ARB), 1, 1, data);

        vm.stopBroadcast();
    }
}