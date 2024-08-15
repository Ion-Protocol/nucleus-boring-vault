// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CrossChainBaseTest, CrossChainTellerBase, ERC20, BridgeData } from "./CrossChainBase.t.sol";
import { CrossChainOPTellerWithMultiAssetSupport } from
    "src/base/Roles/CrossChain/CrossChainOPTellerWithMultiAssetSupport.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";

import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

contract CrossChainOPTellerWithMultiAssetSupportTest is CrossChainBaseTest {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

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

    // op sepolia
    address constant DESTINATION_MESSENGER = 0x4200000000000000000000000000000000000007;

    // mainnet sepolia
    address constant SOURCE_MESSENGER = 0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1;

    function setUp() public virtual override(CrossChainBaseTest) {
        CrossChainBaseTest.setUp();
        CrossChainOPTellerWithMultiAssetSupport(sourceTellerAddr).setGasBounds(0, uint32(CHAIN_MESSAGE_GAS_LIMIT));
        CrossChainOPTellerWithMultiAssetSupport(destinationTellerAddr).setGasBounds(0, uint32(CHAIN_MESSAGE_GAS_LIMIT));
    }

    function testBridgingShares(uint256 sharesToBridge) public virtual {
        CrossChainOPTellerWithMultiAssetSupport sourceTeller = CrossChainOPTellerWithMultiAssetSupport(sourceTellerAddr);
        CrossChainOPTellerWithMultiAssetSupport destinationTeller =
            CrossChainOPTellerWithMultiAssetSupport(destinationTellerAddr);

        sharesToBridge = uint96(bound(sharesToBridge, 1, 1000e18));

        // Bridge shares.
        address to = vm.addr(1);

        BridgeData memory data = BridgeData({
            chainSelector: DESTINATION_SELECTOR,
            destinationChainReceiver: to,
            bridgeFeeToken: WETH,
            messageGas: 80_000,
            data: ""
        });

        uint256 quote = 0;

        bytes memory expectedData = "";
        vm.expectEmit();
        // Not testing for these. Because it's pretty complicated.
        // Figuring out how to get the correct opaque data and message nonce for a fuzz test is a bit out of scope for
        // this test at the moment
        // emit TransactionDeposited(address(this), DESTINATION_MESSENGER, 0, expectedData);
        // emit SentMessage(destinationTellerAddr, sourceTellerAddr, expectedData, 1, 80_000);

        emit SentMessageExtension1(sourceTellerAddr, 0);

        uint256 balBefore = boringVault.balanceOf(address(this));
        bytes32 id = sourceTeller.bridge{ value: quote }(sharesToBridge, data);

        assertEq(boringVault.balanceOf(address(this)), balBefore - sharesToBridge, "Should have burned shares.");
    }

    function testUniqueIDs() public virtual {
        CrossChainOPTellerWithMultiAssetSupport sourceTeller = CrossChainOPTellerWithMultiAssetSupport(sourceTellerAddr);
        CrossChainOPTellerWithMultiAssetSupport destinationTeller =
            CrossChainOPTellerWithMultiAssetSupport(destinationTellerAddr);

        uint256 sharesToBridge = 12;

        // Bridge shares.
        address to = vm.addr(1);

        BridgeData memory data = BridgeData({
            chainSelector: DESTINATION_SELECTOR,
            destinationChainReceiver: to,
            bridgeFeeToken: WETH,
            messageGas: 80_000,
            data: ""
        });

        uint256 quote = 0;

        uint256 balBefore = boringVault.balanceOf(address(this));
        bytes32 id1 = sourceTeller.bridge{ value: quote }(sharesToBridge, data);

        // perform the exact same bridge again and assert the ids are not the same
        bytes32 id2 = sourceTeller.bridge{ value: quote }(sharesToBridge, data);

        assertNotEq(id1, id2, "Id's must be unique");
    }

    function testDepositAndBridge(uint256 amount) external {
        CrossChainOPTellerWithMultiAssetSupport sourceTeller = CrossChainOPTellerWithMultiAssetSupport(sourceTellerAddr);
        CrossChainOPTellerWithMultiAssetSupport destinationTeller =
            CrossChainOPTellerWithMultiAssetSupport(destinationTellerAddr);

        amount = bound(amount, 0.0001e18, 10_000e18);
        // make a user and give them WETH
        address user = makeAddr("A user");
        address userChain2 = makeAddr("A user on chain 2");
        deal(address(WETH), user, amount);

        // approve teller to spend WETH
        vm.startPrank(user);
        vm.deal(user, 10e18);
        WETH.approve(address(boringVault), amount);

        // perform depositAndBridge
        BridgeData memory data = BridgeData({
            chainSelector: DESTINATION_SELECTOR,
            destinationChainReceiver: userChain2,
            bridgeFeeToken: WETH,
            messageGas: 80_000,
            data: ""
        });

        uint256 ONE_SHARE = 10 ** boringVault.decimals();

        uint256 shares = amount.mulDivDown(ONE_SHARE, accountant.getRateInQuoteSafe(WETH));
        uint256 quote = 0;

        uint256 wethBefore = WETH.balanceOf(address(boringVault));

        vm.expectEmit();
        emit SentMessageExtension1(sourceTellerAddr, 0);
        sourceTeller.depositAndBridge{ value: quote }(WETH, amount, shares, data);

        assertEq(boringVault.balanceOf(user), 0, "Should have burned shares.");

        assertEq(WETH.balanceOf(address(boringVault)), wethBefore + shares);
    }

    function testReverts() public virtual override {
        CrossChainOPTellerWithMultiAssetSupport sourceTeller = CrossChainOPTellerWithMultiAssetSupport(sourceTellerAddr);
        CrossChainOPTellerWithMultiAssetSupport destinationTeller =
            CrossChainOPTellerWithMultiAssetSupport(destinationTellerAddr);

        super.testReverts();

        BridgeData memory data =
            BridgeData(DESTINATION_SELECTOR, address(this), ERC20(NATIVE), 80_000, abi.encode(DESTINATION_SELECTOR));

        // reverts with gas too low
        sourceTeller.setGasBounds(uint32(CHAIN_MESSAGE_GAS_LIMIT), uint32(CHAIN_MESSAGE_GAS_LIMIT));
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CrossChainOPTellerWithMultiAssetSupport
                        .CrossChainOPTellerWithMultiAssetSupport_GasOutOfBounds
                        .selector,
                    uint32(80_000)
                )
            )
        );
        sourceTeller.bridge{ value: 0 }(1e18, data);

        // reverts with gas too high
        sourceTeller.setGasBounds(uint32(0), uint32(79_999));
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CrossChainOPTellerWithMultiAssetSupport
                        .CrossChainOPTellerWithMultiAssetSupport_GasOutOfBounds
                        .selector,
                    uint32(80_000)
                )
            )
        );
        sourceTeller.bridge{ value: 0 }(1e18, data);

        // reverts with a fee provided
        sourceTeller.setGasBounds(uint32(0), uint32(CHAIN_MESSAGE_GAS_LIMIT));
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CrossChainOPTellerWithMultiAssetSupport.CrossChainOPTellerWithMultiAssetSupport_NoFee.selector
                )
            )
        );
        sourceTeller.bridge{ value: 1 }(1e18, data);

        // Call now succeeds.
        sourceTeller.bridge{ value: 0 }(1e18, data);
    }

    function _deploySourceAndDestinationTeller() internal virtual override {
        sourceTellerAddr = address(
            new CrossChainOPTellerWithMultiAssetSupport(
                address(this), address(boringVault), address(accountant), SOURCE_MESSENGER
            )
        );
        destinationTellerAddr = address(
            new CrossChainOPTellerWithMultiAssetSupport(
                address(this), address(boringVault), address(accountant), DESTINATION_MESSENGER
            )
        );
    }
}
