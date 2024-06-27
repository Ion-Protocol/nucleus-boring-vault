// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ICrosschainTeller, ERC20, BridgeData} from "../../../interfaces/ICrossChainTeller.sol";
import {TellerWithMultiAssetSupport} from "../TellerWithMultiAssetSupport.sol";

abstract contract CrossChainTellerBase is ICrosschainTeller, TellerWithMultiAssetSupport{
        
    constructor(address _owner, address _vault, address _accountant, address _weth)
        TellerWithMultiAssetSupport(_owner, _vault, _accountant, _weth)
    {

    }

    function addChain(uint chainId, address target, uint gasLimit) external requiresAuth{

    }

    function stopMessagesFromChain(uint chainId) external requiresAuth{

    }

    function allowMessagesFromChain(uint chainId) external requiresAuth{

    }

    function setTargetTeller(address target) external requiresAuth{

    }
    

    /**
     * @dev function to deposit into the vault AND bridge cosschain in 1 call
     * @param depositAsset ERC20 to deposit
     * @param depositAmount amount of deposit asset to deposit
     * @param minimumMint minimum required shares to receive
     * @param data Bridge Data
     */
    function depositAndBridge(ERC20 depositAsset, uint256 depositAmount, uint256 minimumMint, BridgeData calldata data) external{
        uint256 shareAmount = deposit(depositAsset, depositAmount, minimumMint);
        bridge(shareAmount, data);
    }

    /**
     * @dev bridging code to be done without deposit, for users who already have vault tokens
     * @param shareAmount to bridge
     * @param data bridge data
     */
    function bridge(uint256 shareAmount, BridgeData calldata data) public{
        _beforeBridge(shareAmount, data);
        bytes32 messageId = _bridge(data);
        _afterBridge(shareAmount, data, messageId);
    }

    /**
     * @dev code to run before bridging, includes checks and a burn of shares
     * @dev in the CrossChainTellerWithGenericBridge implementation this is inspired by, some data processing is done beforehand,
     * here that is not done in case other implementations need more flexibility. But I will check to see if it should be done here.
     * @param shareAmount to burn
     * @param data unused but potentially needed in an override
     */
    function _beforeBridge(uint256 shareAmount, BridgeData calldata data) internal virtual{
        if(isPaused) revert TellerWithMultiAssetSupport__Paused();
        // Since shares are directly burned, call `beforeTransfer` to enforce before transfer hooks.
        beforeTransfer(msg.sender);

        // Burn shares from sender
        vault.exit(address(0), ERC20(address(0)), 0, msg.sender, shareAmount);
    }

    /**
     * @dev the virtual bridge function to be overriden
     * @param data bridge data
     * @return messageId
     */
    function _bridge(BridgeData calldata data) internal virtual returns(bytes32){
        return 0;
    }

    /**
     * @dev after bridge code, just an emit but can be overriden
     * @param shareAmount share amount burned
     * @param data bridge data
     * @param messageId message id returned when bridged
     */
    function _afterBridge(uint256 shareAmount, BridgeData calldata data, bytes32 messageId) internal virtual{
        emit MessageSent(messageId, shareAmount, data.destinationChainReceiver);
    }
}