

// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {CrossChainTellerBase, BridgeData, ERC20} from "./CrossChainTellerBase.sol";
import { Auth } from "@solmate/auth/Auth.sol";
import {IBridge} from "@arbitrum/nitro-contracts/bridge/IBridge.sol";
import {IInbox} from "@arbitrum/nitro-contracts/bridge/IInbox.sol";
import {ArbSys} from "@arbitrum/nitro-contracts/precompiles/ArbSys.sol";
import {Outbox} from "@arbitrum/nitro-contracts/bridge/Outbox.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/libraries/AddressAliasHelper.sol";

ArbSys constant ARBSYS = ArbSys(0x000000000000000000000000000000000000006E);
/**
 * @title CrossChainLayerZeroTellerWithMultiAssetSupport
 * @notice Arbitrum Bridge implementation of CrossChainTeller
 * Arbitrum is a bit unique as it has different logic for L1 -> L2 and L2 -> L1
 * So to best organize this we have made CrossChainARBTellerWithMultiAssetSupport abstract,
 * and create 2 children as L1 and L2 tellers to be deployed respectively
 */
abstract contract CrossChainARBTellerWithMultiAssetSupport is CrossChainTellerBase {

    IBridge public immutable bridge;

    address public peer;

    uint32 public maxMessageGas;
    uint32 public minMessageGas;

    error CrossChainARBTellerWithMultiAssetSupport_OnlyMessenger();
    error CrossChainARBTellerWithMultiAssetSupport_OnlyPeerAsSender();
    error CrossChainARBTellerWithMultiAssetSupport_NoFee();
    error CrossChainARBTellerWithMultiAssetSupport_GasOutOfBounds(uint32);

    constructor(address _owner, address _vault, address _accountant, address _weth)
        CrossChainTellerBase(_owner, _vault, _accountant, _weth)
    {
        peer = address(this);
    }

    /**
     * Callable by OWNER_ROLE.
     * @param _peer new peer to set
     */
    function setPeer(address _peer) external requiresAuth{
        peer = _peer;
    }

    /**
     * @dev Callable by OWNER_ROLE.
     * @param newMinMessageGas the new minMessageGas bound
     * @param newMaxMessageGas the new maxMessageGas bound
     */
    function setGasBound(uint32 newMinMessageGas, uint32 newMaxMessageGas) external requiresAuth {
        minMessageGas = newMinMessageGas;
        maxMessageGas = newMaxMessageGas;
    }

    /**
     * @notice Function for ARB Messenger to call to receive a message and mint the shares on this chain
     * @param receiver to receive the shares
     * @param shareMintAmount amount of shares to mint
     */
    function receiveBridgeMessage(address receiver, uint256 shareMintAmount) external virtual;

    /**
     * @notice before bridge hook to check gas bound
     * @param data bridge data
     */
    function _beforeBridge(BridgeData calldata data) internal override{
        uint32 messageGas = uint32(data.messageGas);
        if(messageGas > maxMessageGas || messageGas < minMessageGas){
            revert CrossChainARBTellerWithMultiAssetSupport_GasOutOfBounds(messageGas);
        }
    }

}

/**
 * @title CrossChainARBTellerWithMultiAssetSupportL1
 * @notice This is the version of the Arbitrum teller to be deployed on L1
 */
contract CrossChainARBTellerWithMultiAssetSupportL1 is CrossChainARBTellerWithMultiAssetSupport{
    IInbox public inbox;
    constructor(address _owner, address _vault, address _accountant, address _weth, address _inbox)
    CrossChainARBTellerWithMultiAssetSupport(_owner, _vault, _accountant, _weth){
        inbox = IInbox(_inbox);
    }

    function receiveBridgeMessage(address receiver, uint256 shareMintAmount) external override {
        IBridge bridge = inbox.bridge();
        // this prevents reentrancies on L2 to L1 txs
        if (msg.sender != address(bridge)){
            revert CrossChainARBTellerWithMultiAssetSupport_OnlyMessenger();
        }
        Outbox outbox = Outbox(bridge.activeOutbox());
        address l2Sender = outbox.l2ToL1Sender();
        if(l2Sender != outbox.l2ToL1Sender()){
            revert CrossChainARBTellerWithMultiAssetSupport_OnlyPeerAsSender();
        }

        vault.enter(address(0), ERC20(address(0)), 0, receiver, shareMintAmount);
    }

    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee)
        public
        view
        returns (uint256)
    {
        // Use current block basefee if baseFee parameter is 0
        return (1400 + 6 * dataLength) * (baseFee == 0 ? block.basefee : baseFee);
    }

    /**
     * @notice the virtual function to override to get bridge fees
     * @param shareAmount to send
     * @param data bridge data
     */
    function _quote(uint256 shareAmount, BridgeData calldata data) internal view override returns(uint256){
        bytes memory b = abi.encode(shareAmount);

        uint submissionFee = calculateRetryableSubmissionFee(b.length, block.basefee);
        return (submissionFee + 0 + maxMessageGas * data.messageGas);
    }

    /**
     * @notice the virtual bridge function to execute Optimism messenger sendMessage()
     * @param data bridge data
     * @return messageId
     */
    function _bridge(uint256 shareAmount, BridgeData calldata data) internal override returns(bytes32){
        
        /*
            address to,
            uint256 l2CallValue,
            uint256 maxSubmissionCost,
            address excessFeeRefundAddress,
            address callValueRefundAddress,
            uint256 gasLimit,
            uint256 maxFeePerGas,
            bytes calldata data
        */
        uint maxSubmissionCost = calculateRetryableSubmissionFee(abi.encode(shareAmount).length, block.basefee);
        uint256 msgNum = inbox.createRetryableTicket{value: msg.value}(
            data.destinationChainReceiver, 
            0, 
            maxSubmissionCost, 
            msg.sender, 
            msg.sender, 
            maxMessageGas, 
            data.messageGas, 
            abi.encode(shareAmount)
        );

        return bytes32(msgNum);

    }
    
}

/**
 * @title CrossChainARBTellerWithMultiAssetSupportL2 
 * @notice This is the version of the Arbitrum teller to be deployed on L2 
 */
contract CrossChainARBTellerWithMultiAssetSupportL2 is CrossChainARBTellerWithMultiAssetSupport{
    IBridge arbBridge;

    constructor(address _owner, address _vault, address _accountant, address _weth, address _arbBridge)
    CrossChainARBTellerWithMultiAssetSupport(_owner, _vault, _accountant, _weth){
        arbBridge = IBridge(_arbBridge);
    }

    function receiveBridgeMessage(address receiver, uint256 shareMintAmount) external override{
        require(
            msg.sender == AddressAliasHelper.applyL1ToL2Alias(peer),
            "Greeting only updateable by L1"
        );
        vault.enter(address(0), ERC20(address(0)), 0, receiver, shareMintAmount);
    }

    /**
     * @notice the virtual function to override to get bridge fees
     * @param shareAmount to send
     * @param data bridge data
     */
    function _quote(uint256 shareAmount, BridgeData calldata data) internal view override returns(uint256){
        return 0;
    }

    /**
     * @notice the virtual bridge function to execute Optimism messenger sendMessage()
     * @param data bridge data
     * @return messageId
     */
    function _bridge(uint256 shareAmount, BridgeData calldata data) internal override returns(bytes32){
        bytes memory call_data = abi.encodeWithSelector(CrossChainARBTellerWithMultiAssetSupport.receiveBridgeMessage.selector, data.destinationChainReceiver, shareAmount);
        ARBSYS.sendTxToL1(peer, call_data);
    }


}