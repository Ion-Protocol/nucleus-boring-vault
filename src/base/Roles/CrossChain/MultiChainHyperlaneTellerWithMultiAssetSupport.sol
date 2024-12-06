// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {
    MultiChainTellerBase,
    MultiChainTellerBase_MessagesNotAllowedFrom,
    MultiChainTellerBase_MessagesNotAllowedFromSender,
    Chain
} from "./MultiChainTellerBase.sol";
import { BridgeData, ERC20 } from "./CrossChainTellerBase.sol";
import { StandardHookMetadata } from "./Hyperlane/StandardHookMetadata.sol";
import { IMailbox } from "../../../interfaces/hyperlane/IMailbox.sol";

/**
 * @title MultiChainHyperlaneTellerWithMultiAssetSupport
 * @notice Hyperlane implementation of MultiChainTeller
 * @custom:security-contact security@molecularlabs.io
 */
contract MultiChainHyperlaneTellerWithMultiAssetSupport is MultiChainTellerBase {
    // ========================================= STATE =========================================

    /**
     * @notice The hyperlane mailbox contract.
     */
    IMailbox public immutable mailbox;

    /**
     * @notice A nonce used to generate unique message IDs.
     */
    uint128 public nonce;

    //============================== ERRORS ===============================

    error MultiChainHyperlaneTeller_InvalidToken();
    error MultiChainHyperlaneTeller_CallerMustBeMailbox(address caller);

    constructor(
        address _owner,
        address _vault,
        address _accountant,
        IMailbox _mailbox
    )
        MultiChainTellerBase(_owner, _vault, _accountant)
    {
        mailbox = _mailbox;
    }

    /**
     * @notice function override to return the fee quote
     * @param shareAmount to be sent as a message
     * @param data Bridge data
     * @returns fee to be paid for bridging
     */
    function _quote(uint256 shareAmount, BridgeData calldata data) internal view override returns (uint256) {
        bytes memory _payload = abi.encode(shareAmount, data.destinationChainReceiver);
        bytes32 msgRecipient = _addressToBytes32(selectorToChains[data.chainSelector].targetTeller);

        return mailbox.quoteDispatch(data.chainSelector, msgRecipient, _payload); // TODO Should there be hook metadata
            // for quoteDispatch?
    }

    /**
     * @notice Called when data is received from the protocol. It overrides the equivalent function in the parent
     * contract.
     * Protocol messages are defined as packets, comprised of the following parameters.
     * @param origin A struct containing information about where the packet came from.
     * @param sender The contract that sent this message.
     * @param payload Encoded message.
     */
    function handle(uint32 origin, bytes32 sender, bytes calldata payload) external payable {
        _beforeReceive();

        Chain memory chain = selectorToChains[origin];

        // Three things must be checked.
        // 1. This function must only be called by the mailbox
        // 2. The sender must be the teller from the source chain
        // 3. The origin aka chainSelector must be allowed to send message to this
        // contract through the `Chain` config.

        // TODO How does setting the ISM work? Is it necessary?
        if (msg.sender != address(mailbox)) {
            revert MultiChainHyperlaneTeller_CallerMustBeMailbox(msg.sender);
        }

        // TODO check that bytes32 to address works properly
        if (sender != _addressToBytes32(chain.targetTeller)) {
            revert MultiChainTellerBase_MessagesNotAllowedFromSender(uint256(origin), _bytes32ToAddress(sender));
        }

        if (!chain.allowMessagesFrom) {
            revert MultiChainTellerBase_MessagesNotAllowedFrom(origin);
        }

        (uint256 shareAmount, address receiver, bytes32 messageId) = abi.decode(payload, (uint256, address, bytes32));
        vault.enter(address(0), ERC20(address(0)), 0, receiver, shareAmount);

        _afterReceive(shareAmount, receiver, messageId);
    }

    /**
     * @notice bridge override to allow bridge logic to be done for bridge() and depositAndBridge()
     * @param shareAmount to be moved across chain
     * @param data BridgeData
     * @return messageId a unique hash for the message
     */
    function _bridge(uint256 shareAmount, BridgeData calldata data) internal override returns (bytes32 messageId) {
        unchecked {
            messageId = keccak256(abi.encodePacked(++nonce, address(this), block.chainid));
        }

        bytes memory _payload = abi.encode(shareAmount, data.destinationChainReceiver, messageId);

        // Unlike L0 that has a built in peer check, this contract must
        // constrain the message recipient itself. We do this by our own
        // configuration.
        bytes32 msgRecipient = _addressToBytes32(selectorToChains[data.chainSelector].targetTeller);

        bytes32 messageId = mailbox.dispatch{ value: msg.value }(
            data.chainSelector, // must be `destinationDomain` on hyperlane
            msgRecipient, // must be the teller address left-padded to bytes32
            _payload,
            StandardHookMetadata.overrideGasLimit(data.messageGas) // Sets the refund address to msg.sender, sets
                // `_msgValue`
                // to zero
        );
    }

    function _addressToBytes32(address _address) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_address)));
    }

    function _bytes32ToAddress(bytes32 _address) internal pure returns (address) {
        return address(uint160(uint256(_address)));
    }
}
