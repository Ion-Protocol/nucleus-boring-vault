

// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {CrossChainTellerBase, BridgeData, ERC20} from "./CrossChainTellerBase.sol";
import { Auth } from "@solmate/auth/Auth.sol";

interface ICrossDomainMessenger {
    function xDomainMessageSender() external view returns (address);
    function sendMessage(
        address _target,
        bytes calldata _message,
        uint32 _gasLimit
    ) external;
}

/**
 * @title CrossChainLayerZeroTellerWithMultiAssetSupport
 * @notice LayerZero implementation of CrossChainTeller 
 */
contract CrossChainOPTellerWithMultiAssetSupport is CrossChainTellerBase {

    ICrossDomainMessenger public messenger;
    address public peer;

    error CrossChainOPTellerWithMultiAssetSupport_OnlyMessenger();
    error CrossChainOPTellerWithMultiAssetSupport_OnlyPeerAsSender();
    error CrossChainOPTellerWithMultiAssetSupport_NoFee();

    constructor(address _owner, address _vault, address _accountant, address _weth, address _messenger)
        CrossChainTellerBase(_owner, _vault, _accountant, _weth)
    {
        messenger = ICrossDomainMessenger(_messenger);
        peer = address(this);
    }

    /**
     * @notice the virtual bridge function to execute Optimism messenger sendMessage()
     * @param data bridge data
     * @return messageId
     */
    function _bridge(uint256 shareAmount, BridgeData calldata data) internal override returns(bytes32){
        messenger.sendMessage(
            peer,
            abi.encodeCall(
                this.receiveBridgeMessage,
                (
                    data.destinationChainReceiver,
                    shareAmount
                )
            ),
            uint32(data.messageGas)
        );
        return bytes32(0);
    }

    /**
     * @notice function for owner to set the peer, which is by default this address (as usually we use CREATEX to create contracts with the same address)
     * This is because we need to be sure only the peer teller accross chain can mint shares
     * @dev Callable by OWNER_ROLE.
     */
    function setPeer(address _newPeer) external requiresAuth{
        peer = _newPeer;
    }

    /**
     * @notice Function for OP Messenger to call to receive a message and mint the shares on this chain
     * @param receiver to receive the shares
     * @param shareMintAmount amount of shares to mint
     */
    function receiveBridgeMessage(address receiver, uint256 shareMintAmount) external{

        if(msg.sender != address(messenger)){
            revert CrossChainOPTellerWithMultiAssetSupport_OnlyMessenger();
        }

        if(messenger.xDomainMessageSender() != peer){
            revert CrossChainOPTellerWithMultiAssetSupport_OnlyPeerAsSender();
        }

        vault.enter(address(0), ERC20(address(0)), 0, receiver, shareMintAmount);
    }

    /**
     * @notice the virtual function to override to get bridge fees
     * @param shareAmount to send
     * @param data bridge data
     */
    function _quote(uint256 shareAmount, BridgeData calldata data) internal view override returns(uint256){
        revert CrossChainOPTellerWithMultiAssetSupport_NoFee();
    }

}
