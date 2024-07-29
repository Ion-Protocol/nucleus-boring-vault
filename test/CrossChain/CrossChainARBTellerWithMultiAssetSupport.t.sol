// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {CrossChainBaseTest, CrossChainTellerBase, ERC20, BridgeData} from "./CrossChainBase.t.sol";
import {
    CrossChainARBTellerWithMultiAssetSupport, 
    CrossChainARBTellerWithMultiAssetSupportL1, 
    CrossChainARBTellerWithMultiAssetSupportL2
    } from "src/base/Roles/CrossChain/CrossChainARBTellerWithMultiAssetSupport.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {IBridge} from "@arbitrum/nitro-contracts/bridge/IBridge.sol";
import {IInbox} from "@arbitrum/nitro-contracts/bridge/IInbox.sol";
import {console2} from "forge-std/Test.sol";

contract CrossChainARBTellerWithMultiAssetSupportTest is CrossChainBaseTest{
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint;

    event MessageDelivered(
        uint256 indexed messageIndex,
        bytes32 indexed beforeInboxAcc,
        address inbox,
        uint8 kind,
        address sender,
        bytes32 messageDataHash,
        uint256 baseFeeL1,
        uint64 timestamp
    );

    event InboxMessageDelivered(uint256 indexed messageNum, bytes data);

    // we can't use any kind of testing framework for ARB
    // so instead just check for these events coming up on bridge()

    // arb sepolia
    IBridge constant DESTINATION_BRIDGE = IBridge(0x000000000000000000000000000000000000006E);
    IInbox constant DESTINATION_INBOX = IInbox(0x000000000000000000000000000000000000006E);

    // mainnet
    IBridge constant SOURCE_BRIDGE = IBridge(0x8315177aB297bA92A06054cE80a67Ed4DBd7ed3a);
    IInbox constant SOURCE_INBOX = IInbox(0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f);

    function setUp() public virtual override(CrossChainBaseTest){
        CrossChainBaseTest.setUp();
        CrossChainARBTellerWithMultiAssetSupportL1(sourceTellerAddr).setGasBounds(0, uint32(CHAIN_MESSAGE_GAS_LIMIT));
        CrossChainARBTellerWithMultiAssetSupportL2(destinationTellerAddr).setGasBounds(0, uint32(CHAIN_MESSAGE_GAS_LIMIT));
    }

    function testBridgingShares(uint256 sharesToBridge) external {
        CrossChainARBTellerWithMultiAssetSupportL1 sourceTeller = CrossChainARBTellerWithMultiAssetSupportL1(sourceTellerAddr);
        CrossChainARBTellerWithMultiAssetSupportL2 destinationTeller = CrossChainARBTellerWithMultiAssetSupportL2(destinationTellerAddr);

        // L1 Bridge
        sharesToBridge = uint96(bound(sharesToBridge, 1, 1_000e18));
        address user = makeAddr("A user");
        deal(address(boringVault), user, sharesToBridge);
        vm.deal(user, 1e18);
        vm.startPrank(user);
        // Get the bridge data set up
        address to = vm.addr(1);

        BridgeData memory data = BridgeData({
            chainSelector: DESTINATION_SELECTOR,
            destinationChainReceiver: to,
            bridgeFeeToken: ERC20(NATIVE),
            messageGas: 80_000,
            data: ""
        });

        // calculate quote
        uint quote = sourceTeller.previewFee(sharesToBridge, data);

        // get event data
        uint count = SOURCE_BRIDGE.delayedMessageCount();
        bytes memory encodedShares = abi.encode(sharesToBridge);
        bytes memory expectedData = 
        abi.encodePacked(
            uint256(uint160(to)),
            uint256(0),
            quote,
            sourceTeller.calculateRetryableSubmissionFee(encodedShares.length, block.basefee),
            uint256(uint160(user)),
            uint256(uint160(user)),
            uint256(CHAIN_MESSAGE_GAS_LIMIT),
            uint256(data.messageGas),
            encodedShares.length,
            encodedShares
        );

        // expect L1 deposit emit
        vm.expectEmit();
        emit InboxMessageDelivered(count, expectedData);
        bytes32 id = sourceTeller.bridge{value:quote}(sharesToBridge, data);
        
        vm.stopPrank();
        // L2 Bridge

        // set up L2 fork
        // Foundry doesn't aknowledge precompiles...
        // May have to just testnet this
        // _startFork("ARBITRUM_MAINNET_RPC_URL", 	66829720);
        // vm.startPrank(user);

        // // Get the bridge data set up
        // data = BridgeData({
        //     chainSelector: SOURCE_SELECTOR,
        //     destinationChainReceiver: to,
        //     bridgeFeeToken: ERC20(NATIVE),
        //     messageGas: 80_000,
        //     data: ""
        // });

        // // expect L2 deposit emit
        // vm.expectEmit();
        // destinationTeller.bridge(sharesToBridge, data);
        // vm.stopPrank();
    }

    function testDepositAndBridge(uint256 amount) external{
        CrossChainARBTellerWithMultiAssetSupportL1 sourceTeller = CrossChainARBTellerWithMultiAssetSupportL1(sourceTellerAddr);
        CrossChainARBTellerWithMultiAssetSupportL2 destinationTeller = CrossChainARBTellerWithMultiAssetSupportL2(destinationTellerAddr);

        amount = bound(amount, 0.0001e18, 10_000e18);
        // make a user and give them WETH
        address user = makeAddr("A user");
        address userChain2 = makeAddr("A user on chain 2");
        deal(address(WETH), user, amount);

        // approve teller to spend WETH
        vm.startPrank(user);
        vm.deal(user, 10e18);
        WETH.approve(address(boringVault), amount);

        // preform depositAndBridge
        BridgeData memory data = BridgeData({
            chainSelector: DESTINATION_SELECTOR,
            destinationChainReceiver: userChain2,
            bridgeFeeToken: ERC20(NATIVE),
            messageGas: 80_000,
            data: ""
        });

        uint ONE_SHARE = 10 ** boringVault.decimals();

        uint shares = amount.mulDivDown(ONE_SHARE, accountant.getRateInQuoteSafe(WETH));

        uint quote = sourceTeller.previewFee(shares, data);
        uint count = SOURCE_BRIDGE.delayedMessageCount();

        // get the event data expected
        bytes memory encodedShares = abi.encode(shares);
        bytes memory expectedData = 
        abi.encodePacked(
            uint256(uint160(userChain2)),
            uint256(0),
            quote,
            sourceTeller.calculateRetryableSubmissionFee(encodedShares.length, block.basefee),
            uint256(uint160(user)),
            uint256(uint160(user)),
            uint256(CHAIN_MESSAGE_GAS_LIMIT),
            uint256(data.messageGas),
            encodedShares.length,
            encodedShares
        );

        vm.expectEmit();
        emit InboxMessageDelivered(count, expectedData);
        sourceTeller.depositAndBridge{value:quote}(WETH, amount, shares, data);

    }

    function testReverts() public override {
        CrossChainARBTellerWithMultiAssetSupportL1 sourceTeller = CrossChainARBTellerWithMultiAssetSupportL1(sourceTellerAddr);
        CrossChainARBTellerWithMultiAssetSupportL2 destinationTeller = CrossChainARBTellerWithMultiAssetSupportL2(destinationTellerAddr);

        super.testReverts();

        uint sharesToBridge = 1e18;

        BridgeData memory data = BridgeData(DESTINATION_SELECTOR, address(this), ERC20(NATIVE), 80_000, abi.encode(DESTINATION_SELECTOR));
        uint quote = sourceTeller.previewFee(sharesToBridge, data);
        
        // reverts with gas too low
        sourceTeller.setGasBounds(uint32(CHAIN_MESSAGE_GAS_LIMIT), uint32(CHAIN_MESSAGE_GAS_LIMIT));
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainARBTellerWithMultiAssetSupport.CrossChainARBTellerWithMultiAssetSupport_GasOutOfBounds.selector, uint32(80_000)))
        );
        sourceTeller.bridge{value:quote}(sharesToBridge, data);

        // reverts with gas too high
        sourceTeller.setGasBounds(uint32(0), uint32(79_999));
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainARBTellerWithMultiAssetSupport.CrossChainARBTellerWithMultiAssetSupport_GasOutOfBounds.selector, uint32(80_000)))
        );
        sourceTeller.bridge{value:quote}(sharesToBridge, data);

        sourceTeller.setGasBounds(uint32(0), uint32(CHAIN_MESSAGE_GAS_LIMIT));

        // Call now succeeds.
        sourceTeller.bridge{value:quote}(sharesToBridge, data);

    }

    function _deploySourceAndDestinationTeller() internal override{
        sourceTellerAddr = address(new CrossChainARBTellerWithMultiAssetSupportL1(address(this), address(boringVault), address(accountant), address(SOURCE_INBOX)));
        destinationTellerAddr = address(new CrossChainARBTellerWithMultiAssetSupportL2(address(this), address(boringVault), address(accountant), address(DESTINATION_BRIDGE)));
    }

}
