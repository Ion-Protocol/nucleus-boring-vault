

// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {CrossChainTellerBase, BridgeData, ERC20} from "./CrossChainTellerBase.sol";

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

    constructor(address _owner, address _vault, address _accountant, address _weth, address _messenger)
        CrossChainTellerBase(_owner, _vault, _accountant, _weth)
    {
        messenger = ICrossDomainMessenger(_messenger);
    }

    /**
     * @dev the virtual bridge function to be overridden
     * @param data bridge data
     * @return messageId
     */
    function _bridge(uint256 shareAmount, BridgeData calldata data) internal override returns(bytes32){
        messenger.sendMessage(
            address(selectorToChains[data.chainSelector].targetTeller),
            abi.encodeCall(
                this.receiveBridgeMessage,
                (
                    data.destinationChainReceiver,
                    shareAmount
                )
            ),
            uint32(data.messageGas)
        );
    }

    function receiveBridgeMessage(address receiver, uint256 shareMintAmount) external{
        // TODO
        // Clean this up
        require(
            msg.sender == address(messenger),
            "Greeter: Direct sender must be the CrossDomainMessenger"
        );

        // NOTE
        // this is a duct tape thing for me to get this out quick. 
        // This assumes we deploy this teller and it's peer at the same address
        // What I will need to do (but don't want to right now) is set up an auth
        // And let the owner set the peer as the other address
        require(
            messenger.xDomainMessageSender() == address(this),
            "Greeter: Remote sender must be the other Greeter contract"
        );

        vault.enter(address(0), ERC20(address(0)), 0, receiver, shareMintAmount);
    }

    /**
     * @dev the virtual function to override to get bridge fees
     * @param shareAmount to send
     * @param data bridge data
     */
    function _quote(uint256 shareAmount, BridgeData calldata data) internal view override returns(uint256){

    }

}
