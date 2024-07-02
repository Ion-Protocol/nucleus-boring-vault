// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {CrossChainBaseTest, CrossChainTellerBase} from "./CrossChainBase.t.sol";
import {CrossChainLayerZeroTellerWithMultiAssetSupport} from "src/base/Roles/CrossChain/CrossChainLayerZeroTellerWithMultiAssetSupport.sol";
import "src/interfaces/ICrossChainTeller.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {console} from "@forge-std/Test.sol";

import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {OAppAuthCore} from "src/base/Roles/CrossChain/OAppAuth/OAppAuthCore.sol";

contract CrossChainLayerZeroTellerWithMultiAssetSupportTest is CrossChainBaseTest, TestHelperOz5{
    using SafeTransferLib for ERC20;

    function setUp() public virtual override(CrossChainBaseTest, TestHelperOz5){
        CrossChainBaseTest.setUp();
        TestHelperOz5.setUp();
    }

    function testBridgingShares(uint256 sharesToBridge) external {
        sharesToBridge = uint96(bound(sharesToBridge, 1, 1_000e18));
        uint256 startingShareBalance = boringVault.balanceOf(address(this));
        // Setup chains on bridge.
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 100_000);
        destinationTeller.addChain(SOURCE_SELECTOR, true, true, address(sourceTeller), 100_000);

        // Bridge 100 shares.
        address to = vm.addr(1);

        BridgeData memory data = BridgeData({
            chainId: DESTINATION_SELECTOR,
            destinationChainReceiver: to,
            bridgeFeeToken: WETH,
            maxBridgeFee: 0,
            data: ""
        });

        bytes32 id = sourceTeller.bridge{value:sourceTeller.previewFee(sharesToBridge, data)}(sharesToBridge, data);

        console.log(uint(id));

        verifyPackets(uint32(DESTINATION_SELECTOR), addressToBytes32(address(destinationTeller)));

        assertEq(
            boringVault.balanceOf(address(this)), startingShareBalance - sharesToBridge, "Should have burned shares."
        );

        assertEq(
            boringVault.balanceOf(to), sharesToBridge
        );
    }



    function testReverts() external {
        // Adding a chain with a zero message gas limit should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainLayerZeroTellerWithMultiAssetSupport_ZeroMessageGasLimit.selector))
        );
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 0);

        // Allowing messages to a chain with a zero message gas limit should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainLayerZeroTellerWithMultiAssetSupport_ZeroMessageGasLimit.selector))
        );
        sourceTeller.allowMessagesToChain(DESTINATION_SELECTOR, address(destinationTeller), 0);

        // Changing the gas limit to zero should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainLayerZeroTellerWithMultiAssetSupport_ZeroMessageGasLimit.selector))
        );
        sourceTeller.setChainGasLimit(DESTINATION_SELECTOR, 0);

        // But you can add a chain with a non-zero message gas limit, if messages to are not supported.
        uint64 newChainSelector = 3;
        sourceTeller.addChain(newChainSelector, true, false, address(destinationTeller), 0);

        // If teller is paused bridging is not allowed.
        sourceTeller.pause();
        vm.expectRevert(
            bytes(abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__Paused.selector))
        );

        BridgeData memory data = BridgeData(DESTINATION_SELECTOR, address(0), ERC20(address(0)), 0, "");
        sourceTeller.bridge(0, data);

        sourceTeller.unpause();

        // Trying to send messages to a chain that is not supported should revert.
        uint256 expectedFee = 1e18;
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CrossChainLayerZeroTellerWithMultiAssetSupport_MessagesNotAllowedTo.selector, DESTINATION_SELECTOR
                )
            )
        );

        data = BridgeData(DESTINATION_SELECTOR, address(this), ERC20(address(0)), expectedFee, abi.encode(DESTINATION_SELECTOR));
        sourceTeller.bridge(1e18, data);

        // setup chains.
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 100_000);
        destinationTeller.addChain(SOURCE_SELECTOR, true, true, address(sourceTeller), 100_000);

        // If the max fee is exceeded the transaction should revert.
        // TODO

        // Call now succeeds.
        sourceTeller.bridge{value:expectedFee}(1e18, data);

        // TODO assert this happens

    }

    function _deploySourceAndDestinationTeller() internal override{

        setUpEndpoints(2, LibraryType.UltraLightNode);

        sourceTeller = CrossChainLayerZeroTellerWithMultiAssetSupport(
            _deployOApp(type(CrossChainLayerZeroTellerWithMultiAssetSupport).creationCode, abi.encode(address(this), address(boringVault), address(accountant), address(WETH), endpoints[uint32(SOURCE_SELECTOR)]))
        );

        destinationTeller = CrossChainLayerZeroTellerWithMultiAssetSupport(
            _deployOApp(type(CrossChainLayerZeroTellerWithMultiAssetSupport).creationCode, abi.encode(address(this), address(boringVault), address(accountant), address(WETH), endpoints[uint32(DESTINATION_SELECTOR)]))
        );

        // config and wire the oapps
        address[] memory oapps = new address[](2);
        oapps[0] = address(sourceTeller);
        oapps[1] = address(destinationTeller);
        this.wireOApps(oapps);

        bytes32 peer1 = OAppAuthCore(address(sourceTeller)).peers(uint32(DESTINATION_SELECTOR));
        bytes32 peer2 = OAppAuthCore(address(destinationTeller)).peers(uint32(SOURCE_SELECTOR));

    }

    function _simpleBridgeOne() internal{
        BridgeData memory data = BridgeData({
            chainId: DESTINATION_SELECTOR,
            destinationChainReceiver: payout_address,
            bridgeFeeToken: ERC20(address(0)),
            maxBridgeFee: 0,
            data: ""
        });

        sourceTeller.bridge(1,data);
    }
}
