// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {CrossChainBaseTest} from "./CrossChainBase.t.sol";
import {CrossChainLayerZeroTellerWithMultiAssetSupport} from "src/base/Roles/CrossChain/CrossChainLayerZeroTellerWithMultiAssetSupport.sol";
import "src/interfaces/ICrossChainTeller.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract CrossChainLayerZeroTellerWithMultiAssetSupportTest is CrossChainBaseTest, TestHelperOz5{
    using SafeTransferLib for ERC20;

    function setUp() public virtual override(CrossChainBaseTest, TestHelperOz5){
        TestHelperOz5.setUp();
        CrossChainBaseTest.setUp();
    }

    // note auth is assumed to function properly
    function testAddChain() external{
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), GAS_LIMIT);
        destinationTeller.addChain(SOURCE_SELECTOR, true, true, address(sourceTeller), GAS_LIMIT);

        _simpleBridgeOne();
        assertEq(boringVault.balanceOf(payout_address), 1);

        // test error when destination blocks source chain
        destinationTeller.stopMessagesFromChain(SOURCE_SELECTOR);
        vm.expectRevert(abi.encodeWithSelector(
            CrossChainLayerZeroTellerWithMultiAssetSupport_InvalidChain.selector
        ));
        _simpleBridgeOne();
        destinationTeller.allowMessagesFromChain(SOURCE_SELECTOR);

        // test error when source blocks destination chain
        sourceTeller.stopMessagesFromChain(DESTINATION_SELECTOR);
        vm.expectRevert(abi.encodeWithSelector(
            CrossChainLayerZeroTellerWithMultiAssetSupport_InvalidChain.selector
        ));
        _simpleBridgeOne();
        sourceTeller.allowMessagesFromChain(DESTINATION_SELECTOR);

        // test error when targetTeller isn't correct in destination
        destinationTeller.setTargetTeller(SOURCE_SELECTOR, address(12));
        vm.expectRevert(abi.encodeWithSelector(
            CrossChainLayerZeroTellerWithMultiAssetSupport_InvalidSource.selector
        ));
        _simpleBridgeOne();
        destinationTeller.setTargetTeller(SOURCE_SELECTOR, address(sourceTeller));

    }

    function testBridgingShares(uint256 sharesToBridge) external {
        sharesToBridge = uint96(bound(sharesToBridge, 1, 1_000e18));
        uint256 startingShareBalance = boringVault.balanceOf(address(this));
        // Setup chains on bridge.
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 100_000);
        destinationTeller.addChain(SOURCE_SELECTOR, true, true, address(sourceTeller), 100_000);

        // Bridge 100 shares.
        address to = vm.addr(1);
        uint256 expectedFee = 1e18;
        LINK.safeApprove(address(sourceTeller), expectedFee);

        BridgeData memory data = BridgeData({
            chainId: DESTINATION_SELECTOR,
            destinationChainReceiver: to,
            bridgeFeeToken: LINK,
            maxBridgeFee: 0,
            data: ""
        });

        sourceTeller.bridge(sharesToBridge, data);

        assertEq(
            boringVault.balanceOf(address(this)), startingShareBalance - sharesToBridge, "Should have burned shares."
        );

        assertEq(
            boringVault.balanceOf(to), sharesToBridge
        );
    }



    // function testReverts() external {
    //     // Adding a chain with a zero message gas limit should revert.
    //     vm.expectRevert(
    //         bytes(abi.encodeWithSelector(CrossChainLayerZeroTellerWithMultiAssetSupport.ChainlinkCCIPTeller__ZeroMessageGasLimit.selector))
    //     );
    //     sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 0);

    //     // Allowing messages to a chain with a zero message gas limit should revert.
    //     vm.expectRevert(
    //         bytes(abi.encodeWithSelector(CrossChainLayerZeroTellerWithMultiAssetSupport.ChainlinkCCIPTeller__ZeroMessageGasLimit.selector))
    //     );
    //     sourceTeller.allowMessagesToChain(DESTINATION_SELECTOR, address(destinationTeller), 0);

    //     // Changing the gas limit to zero should revert.
    //     vm.expectRevert(
    //         bytes(abi.encodeWithSelector(CrossChainLayerZeroTellerWithMultiAssetSupport.ChainlinkCCIPTeller__ZeroMessageGasLimit.selector))
    //     );
    //     sourceTeller.setChainGasLimit(DESTINATION_SELECTOR, 0);

    //     // But you can add a chain with a non-zero message gas limit, if messages to are not supported.
    //     uint64 newChainSelector = 3;
    //     sourceTeller.addChain(newChainSelector, true, false, address(destinationTeller), 0);

    //     // If teller is paused bridging is not allowed.
    //     sourceTeller.pause();
    //     vm.expectRevert(
    //         bytes(abi.encodeWithSelector(CrossChainLayerZeroTellerWithMultiAssetSupport.TellerWithMultiAssetSupport__Paused.selector))
    //     );
    //     sourceTeller.bridge(0, address(0), hex"", LINK, 0);

    //     sourceTeller.unpause();

    //     // Trying to send messages to a chain that is not supported should revert.
    //     uint256 expectedFee = 1e18;
    //     vm.expectRevert(
    //         bytes(
    //             abi.encodeWithSelector(
    //                 CrossChainLayerZeroTellerWithMultiAssetSupport.ChainlinkCCIPTeller__MessagesNotAllowedTo.selector, DESTINATION_SELECTOR
    //             )
    //         )
    //     );
    //     sourceTeller.bridge(1e18, address(this), abi.encode(DESTINATION_SELECTOR), LINK, expectedFee);

    //     // setup chains.
    //     sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 100_000);
    //     destinationTeller.addChain(SOURCE_SELECTOR, true, true, address(sourceTeller), 100_000);

    //     // If the max fee is exceeded the transaction should revert.
    //     // TODO


    //     // If user forgets approval call reverts too.
    //     vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
    //     sourceTeller.bridge(1e18, address(this), abi.encode(DESTINATION_SELECTOR), LINK, expectedFee);

    //     // Call now succeeds.
    //     LINK.safeApprove(address(sourceTeller), expectedFee);
    //     sourceTeller.bridge(1e18, address(this), abi.encode(DESTINATION_SELECTOR), LINK, expectedFee);

    //     // TODO assert this happens

    // }

    function _deploySourceAndDestinationTeller() internal override{
        setUpEndpoints(2, LibraryType.UltraLightNode);

        sourceTeller = CrossChainTellerBase(
            _deployOApp(type(CrossChainTellerBase).creationCode, abi.encode("aOFT", "aOFT", address(endpoints[aEid]), address(this)))
        );

        destinationTeller = CrossChainTellerBase(
            _deployOApp(type(CrossChainTellerBase).creationCode, abi.encode("bOFT", "bOFT", address(endpoints[bEid]), address(this)))
        );

        // config and wire the ofts
        address[] memory ofts = new address[](2);
        ofts[0] = address(aOFT);
        ofts[1] = address(bOFT);
        this.wireOApps(ofts);
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
