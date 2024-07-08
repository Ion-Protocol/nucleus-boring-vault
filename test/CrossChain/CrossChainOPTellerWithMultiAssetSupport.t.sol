// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {CrossChainBaseTest, CrossChainTellerBase} from "./CrossChainBase.t.sol";
import {CrossChainOPTellerWithMultiAssetSupport} from "src/base/Roles/CrossChain/CrossChainOPTellerWithMultiAssetSupport.sol";
import "src/interfaces/ICrossChainTeller.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";

import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

contract CrossChainOPTellerWithMultiAssetSupportTest is CrossChainBaseTest{
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint;


    // we can't use any kind of testing framework for OP
    // so instead just check for these events coming up on bridge()

    /// @notice Emitted when a transaction is deposited from L1 to L2.
    ///         The parameters of this event are read by the rollup node and used to derive deposit
    ///         transactions on L2.
    /// @param from       Address that triggered the deposit transaction.
    /// @param to         Address that the deposit transaction is directed to.
    /// @param version    Version of this deposit transaction event.
    /// @param opaqueData ABI encoded deposit data to be parsed off-chain.
    event TransactionDeposited(address indexed from, address indexed to, uint256 indexed version, bytes opaqueData);

    /// @notice Emitted whenever a message is sent to the other chain.
    /// @param target       Address of the recipient of the message.
    /// @param sender       Address of the sender of the message.
    /// @param message      Message to trigger the recipient address with.
    /// @param messageNonce Unique nonce attached to the message.
    /// @param gasLimit     Minimum gas limit that the message can be executed with.
    event SentMessage(address indexed target, address sender, bytes message, uint256 messageNonce, uint256 gasLimit);

    /// @notice Additional event data to emit, required as of Bedrock. Cannot be merged with the
    ///         SentMessage event without breaking the ABI of this contract, this is good enough.
    /// @param sender Address of the sender of the message.
    /// @param value  ETH value sent along with the message to the recipient.
    event SentMessageExtension1(address indexed sender, uint256 value);

    uint64 constant CHAIN_MESSAGE_GAS_LIMIT = 100_000;

    // op sepolia
    address constant DESTINATION_MESSENGER = 0x4200000000000000000000000000000000000007;

    // mainnet sepolia
    address constant SOURCE_MESSENGER = 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1;

    function setUp() public virtual override(CrossChainBaseTest){
        CrossChainBaseTest.setUp();
    }

    function testBridgingShares(uint256 sharesToBridge) external {
        sharesToBridge = uint96(bound(sharesToBridge, 1, 1_000e18));
        // Setup chains on bridge.
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), CHAIN_MESSAGE_GAS_LIMIT);
        destinationTeller.addChain(SOURCE_SELECTOR, true, true, address(sourceTeller), CHAIN_MESSAGE_GAS_LIMIT);

        // Bridge shares.
        address to = vm.addr(1);

        BridgeData memory data = BridgeData({
            chainSelector: DESTINATION_SELECTOR,
            destinationChainReceiver: to,
            bridgeFeeToken: WETH,
            messageGas: 80_000,
            data: ""
        });

        uint quote = 0;

        bytes memory expectedData = "";
        vm.expectEmit();
        // Not testing for these. Because it's pretty complicated.
        // Figuring out how to get the correct opaque data and message nonce for a fuzz test is a bit out of scope for this test at the moment 
        // emit TransactionDeposited(address(this), DESTINATION_MESSENGER, 0, expectedData);
        // emit SentMessage(address(destinationTeller), address(sourceTeller), expectedData, 1, 80_000);

        emit SentMessageExtension1(address(sourceTeller), 0);

        bytes32 id = sourceTeller.bridge{value:quote}(sharesToBridge, data);

    }

    function testDepositAndBridge(uint256 amount) external{

        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 100_000);
        destinationTeller.addChain(SOURCE_SELECTOR, true, true, address(sourceTeller), 100_000);

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
            bridgeFeeToken: WETH,
            messageGas: 80_000,
            data: ""
        });

        uint ONE_SHARE = 10 ** boringVault.decimals();

        uint shares = amount.mulDivDown(ONE_SHARE, accountant.getRateInQuoteSafe(WETH));
        uint quote = 0;

        vm.expectEmit();
        emit SentMessageExtension1(address(sourceTeller), 0);
        sourceTeller.depositAndBridge{value:quote}(WETH, amount, shares, data);

    }


    function testReverts() external {
        // Adding a chain with a zero message gas limit should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainTellerBase_ZeroMessageGasLimit.selector))
        );
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 0);        

        // Allowing messages to a chain with a zero message gas limit should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainTellerBase_ZeroMessageGasLimit.selector))
        );
        sourceTeller.allowMessagesToChain(DESTINATION_SELECTOR, address(destinationTeller), 0);

        // Changing the gas limit to zero should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainTellerBase_ZeroMessageGasLimit.selector))
        );
        sourceTeller.setChainGasLimit(DESTINATION_SELECTOR, 0);

        // But you can add a chain with a non-zero message gas limit, if messages to are not supported.
        uint32 newChainSelector = 3;
        sourceTeller.addChain(newChainSelector, true, false, address(destinationTeller), 0);

        // If teller is paused bridging is not allowed.
        sourceTeller.pause();
        vm.expectRevert(
            bytes(abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__Paused.selector))
        );

        BridgeData memory data = BridgeData(DESTINATION_SELECTOR, address(0), ERC20(address(0)), 80_000, "");
        sourceTeller.bridge(0, data);

        sourceTeller.unpause();

        // Trying to send messages to a chain that is not supported should revert.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CrossChainTellerBase_MessagesNotAllowedTo.selector, DESTINATION_SELECTOR
                )
            )
        );

        data = BridgeData(DESTINATION_SELECTOR, address(this), WETH, 80_000, abi.encode(DESTINATION_SELECTOR));
        sourceTeller.bridge(1e18, data);

        // setup chains.
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 100_000);
        destinationTeller.addChain(SOURCE_SELECTOR, true, true, address(sourceTeller), 100_000);


        // should revert on attempt to quote
        vm.expectRevert(
            abi.encodeWithSelector(
                CrossChainOPTellerWithMultiAssetSupport.CrossChainOPTellerWithMultiAssetSupport_NoFee.selector
            )
        );
        sourceTeller.previewFee(0, data);

        // if too much gas is used, revert
        data = BridgeData(DESTINATION_SELECTOR, address(this), WETH, CHAIN_MESSAGE_GAS_LIMIT+1, abi.encode(DESTINATION_SELECTOR));
        vm.expectRevert(
            abi.encodeWithSelector(
                    CrossChainTellerBase_GasLimitExceeded.selector
            )
        );
        sourceTeller.bridge(1e18, data);


        // Call now succeeds.
        data = BridgeData(DESTINATION_SELECTOR, address(this), WETH, 80_000, abi.encode(DESTINATION_SELECTOR));
        uint quote = 0;

        sourceTeller.bridge{value:quote}(1e18, data);

    }

    function _deploySourceAndDestinationTeller() internal override{
        sourceTeller = new CrossChainOPTellerWithMultiAssetSupport(address(this), address(boringVault), address(accountant), address(WETH), SOURCE_MESSENGER);
        destinationTeller = new CrossChainOPTellerWithMultiAssetSupport(address(this), address(boringVault), address(accountant), address(WETH), DESTINATION_MESSENGER);
    }

}
