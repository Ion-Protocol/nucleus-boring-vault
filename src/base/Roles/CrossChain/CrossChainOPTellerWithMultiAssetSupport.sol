// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { CrossChainTellerBase, BridgeData, ERC20 } from "./CrossChainTellerBase.sol";

interface ICrossDomainMessenger {
    function xDomainMessageSender() external view returns (address);
    function sendMessage(address _target, bytes calldata _message, uint32 _gasLimit) external;
}

/**
 * @title CrossChainLayerZeroTellerWithMultiAssetSupport
 * @notice LayerZero implementation of CrossChainTeller
 */
contract CrossChainOPTellerWithMultiAssetSupport is CrossChainTellerBase {
    ICrossDomainMessenger public immutable messenger;
    address public peer;

    uint32 public maxMessageGas;
    uint32 public minMessageGas;
    uint128 public nonce;

    error CrossChainOPTellerWithMultiAssetSupport_OnlyMessenger();
    error CrossChainOPTellerWithMultiAssetSupport_OnlyPeerAsSender();
    error CrossChainOPTellerWithMultiAssetSupport_NoFee();
    error CrossChainOPTellerWithMultiAssetSupport_GasOutOfBounds(uint32);

    constructor(
        address _owner,
        address _vault,
        address _accountant,
        address _messenger
    )
        CrossChainTellerBase(_owner, _vault, _accountant)
    {
        messenger = ICrossDomainMessenger(_messenger);
        peer = address(this);
    }

    /**
     * Callable by OWNER_ROLE.
     * @param _peer new peer to set
     */
    function setPeer(address _peer) external requiresAuth {
        peer = _peer;
    }

    /**
     * @dev Callable by OWNER_ROLE.
     * @param newMinMessageGas the new minMessageGas bound
     * @param newMaxMessageGas the new maxMessageGas bound
     */
    function setGasBounds(uint32 newMinMessageGas, uint32 newMaxMessageGas) external requiresAuth {
        minMessageGas = newMinMessageGas;
        maxMessageGas = newMaxMessageGas;
    }

    /**
     * @notice Function for OP Messenger to call to receive a message and mint the shares on this chain
     * @param receiver to receive the shares
     * @param shareMintAmount amount of shares to mint
     */
    function receiveBridgeMessage(address receiver, uint256 shareMintAmount, bytes32 messageId) external {
        _beforeReceive();

        if (msg.sender != address(messenger)) {
            revert CrossChainOPTellerWithMultiAssetSupport_OnlyMessenger();
        }

        if (messenger.xDomainMessageSender() != peer) {
            revert CrossChainOPTellerWithMultiAssetSupport_OnlyPeerAsSender();
        }

        vault.enter(address(0), ERC20(address(0)), 0, receiver, shareMintAmount);

        _afterReceive(shareMintAmount, receiver, messageId);
    }

    /**
     * @notice the virtual bridge function to execute Optimism messenger sendMessage()
     * @param data bridge data
     * @return messageId
     */
    function _bridge(uint256 shareAmount, BridgeData calldata data) internal override returns (bytes32 messageId) {
        unchecked {
            messageId = keccak256(abi.encodePacked(++nonce, address(this), block.chainid));
        }

        messenger.sendMessage(
            peer,
            abi.encodeCall(this.receiveBridgeMessage, (data.destinationChainReceiver, shareAmount, messageId)),
            uint32(data.messageGas)
        );
    }

    /**
     * @notice before bridge hook to check gas bound and revert if someone's paying a fee
     * @param data bridge data
     */
    function _beforeBridge(BridgeData calldata data) internal override {
        uint32 messageGas = uint32(data.messageGas);
        if (messageGas > maxMessageGas || messageGas < minMessageGas) {
            revert CrossChainOPTellerWithMultiAssetSupport_GasOutOfBounds(messageGas);
        }
        if (msg.value > 0) {
            revert CrossChainOPTellerWithMultiAssetSupport_NoFee();
        }
    }

    /**
     * @notice the virtual function to override to get bridge fees, always zero for OP
     * @param shareAmount to send
     * @param data bridge data
     */
    // solhint-disable-next-line no-unused-vars
    function _quote(uint256 shareAmount, BridgeData calldata data) internal view override returns (uint256) {
        return 0;
    }
}
