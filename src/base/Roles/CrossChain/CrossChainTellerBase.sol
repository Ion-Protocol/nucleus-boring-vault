// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {TellerWithMultiAssetSupport} from "../TellerWithMultiAssetSupport.sol";
import "../../../interfaces/ICrossChainTeller.sol";
/**
 * @title CrossChainTellerBase
 * @notice Base contract for the CrossChainTeller, includes functions to overload with specific bridge method
 */
abstract contract CrossChainTellerBase is ICrossChainTeller, TellerWithMultiAssetSupport{
    
    mapping(uint32 => Chain) public selectorToChains;

    constructor(address _owner, address _vault, address _accountant, address _weth)
        TellerWithMultiAssetSupport(_owner, _vault, _accountant, _weth)
    {
    }

    // ========================================= ADMIN FUNCTIONS =========================================
    /**
     * @notice Add a chain to the teller.
     * @dev Callable by OWNER_ROLE.
     * @param chainSelector The chain selector to add.
     * @param allowMessagesFrom Whether to allow messages from this chain.
     * @param allowMessagesTo Whether to allow messages to this chain.
     * @param targetTeller The address of the target teller on the other chain.
     * @param messageGasLimit The gas limit for messages to this chain.
     * @param messageGasMin The minimum gas required to be sent for this chain
     */
    function addChain(
        uint32 chainSelector,
        bool allowMessagesFrom,
        bool allowMessagesTo,
        address targetTeller,
        uint64 messageGasLimit,
        uint64 messageGasMin
    ) external requiresAuth {
        if (allowMessagesTo && messageGasLimit == 0) {
            revert CrossChainTellerBase_ZeroMessageGasLimit();
        }
        selectorToChains[chainSelector] = Chain(allowMessagesFrom, allowMessagesTo, targetTeller, messageGasLimit, messageGasMin);

        emit ChainAdded(chainSelector, allowMessagesFrom, allowMessagesTo, targetTeller, messageGasLimit, messageGasMin);
    }

    /**
     * @notice Remove a chain from the teller.
     * @dev Callable by OWNER_ROLE.
     */
    function removeChain(uint32 chainSelector) external requiresAuth {
        delete selectorToChains[chainSelector];

        emit ChainRemoved(chainSelector);
    }

    /**
     * @notice Allow messages from a chain.
     * @dev Callable by OWNER_ROLE.
     */
    function allowMessagesFromChain(uint32 chainSelector, address targetTeller) external requiresAuth {
        Chain storage chain = selectorToChains[chainSelector];
        chain.allowMessagesFrom = true;
        chain.targetTeller = targetTeller;

        emit ChainAllowMessagesFrom(chainSelector, targetTeller);
    }

    /**
     * @notice Allow messages to a chain.
     * @dev Callable by OWNER_ROLE.
     */
    function allowMessagesToChain(uint32 chainSelector, address targetTeller, uint64 messageGasLimit)
        external
        requiresAuth
    {
        if (messageGasLimit == 0) {
            revert CrossChainTellerBase_ZeroMessageGasLimit();
        }
        Chain storage chain = selectorToChains[chainSelector];
        chain.allowMessagesTo = true;
        chain.targetTeller = targetTeller;
        chain.messageGasLimit = messageGasLimit;

        emit ChainAllowMessagesTo(chainSelector, targetTeller);
    }

    /**
     * @notice Stop messages from a chain.
     * @dev Callable by OWNER_ROLE.
     */
    function stopMessagesFromChain(uint32 chainSelector) external requiresAuth {
        Chain storage chain = selectorToChains[chainSelector];
        chain.allowMessagesFrom = false;

        emit ChainStopMessagesFrom(chainSelector);
    }

    /**
     * @notice Stop messages to a chain.
     * @dev Callable by OWNER_ROLE.
     */
    function stopMessagesToChain(uint32 chainSelector) external requiresAuth {
        Chain storage chain = selectorToChains[chainSelector];
        chain.allowMessagesTo = false;

        emit ChainStopMessagesTo(chainSelector);
    }

    /**
     * @notice Set the gas limit for messages to a chain.
     * @dev Callable by OWNER_ROLE.
     */
    function setChainGasLimit(uint32 chainSelector, uint64 messageGasLimit) external requiresAuth {
        if (messageGasLimit == 0) {
            revert CrossChainTellerBase_ZeroMessageGasLimit();
        }
        Chain storage chain = selectorToChains[chainSelector];
        chain.messageGasLimit = messageGasLimit;

        emit ChainSetGasLimit(chainSelector, messageGasLimit);
    }

    
    /**
     * @notice function to deposit into the vault AND bridge crosschain in 1 call
     * @param depositAsset ERC20 to deposit
     * @param depositAmount amount of deposit asset to deposit
     * @param minimumMint minimum required shares to receive
     * @param data Bridge Data
     */
    function depositAndBridge(ERC20 depositAsset, uint256 depositAmount, uint256 minimumMint, BridgeData calldata data) external payable requiresAuth nonReentrant{
    
        if(!isSupported[depositAsset]){
            revert TellerWithMultiAssetSupport__AssetNotSupported();
        }

        uint shareAmount = _erc20Deposit(depositAsset, depositAmount, minimumMint, msg.sender);
        _afterPublicDeposit(msg.sender, depositAsset, depositAmount, shareAmount, shareLockPeriod);
        bridge(shareAmount, data);
    }


    /**
     * @notice Preview fee required to bridge shares in a given feeToken.
     */
    function previewFee(uint256 shareAmount, BridgeData calldata data)
        external
        view
        returns (uint256 fee)
    {
        return _quote(shareAmount, data);
    }

    /**
     * @notice bridging code to be done without deposit, for users who already have vault tokens
     * @param shareAmount to bridge
     * @param data bridge data
     */
    function bridge(uint256 shareAmount, BridgeData calldata data) public payable requiresAuth returns(bytes32 messageId) {
        if(isPaused) revert TellerWithMultiAssetSupport__Paused();
        if(!selectorToChains[data.chainSelector].allowMessagesTo) revert CrossChainTellerBase_MessagesNotAllowedTo(data.chainSelector);
        
        if(data.messageGas > selectorToChains[data.chainSelector].messageGasLimit){
            revert CrossChainTellerBase_GasLimitExceeded();
        }

        if(data.messageGas < selectorToChains[data.chainSelector].minimumMessageGas){
            revert CrossChainTellerBase_GasTooLow();
        }

        // Since shares are directly burned, call `beforeTransfer` to enforce before transfer hooks.
        beforeTransfer(msg.sender);

        // Burn shares from sender
        vault.exit(address(0), ERC20(address(0)), 0, msg.sender, shareAmount);
        
        messageId = _bridge(shareAmount, data);
        _afterBridge(shareAmount, data, messageId);
    }

    /**
     * @notice the virtual bridge function to be overridden
     * @param data bridge data
     * @return messageId
     */
    function _bridge(uint256 shareAmount, BridgeData calldata data) internal virtual returns(bytes32);

    /**
     * @notice the virtual function to override to get bridge fees
     * @param shareAmount to send
     * @param data bridge data
     */
    function _quote(uint256 shareAmount, BridgeData calldata data) internal view virtual returns(uint256);

    /**
     * @notice after bridge code, just an emit but can be overriden
     * @param shareAmount share amount burned
     * @param data bridge data
     * @param messageId message id returned when bridged
     */
    function _afterBridge(uint256 shareAmount, BridgeData calldata data, bytes32 messageId) internal virtual{
        emit MessageSent(messageId, shareAmount, data.destinationChainReceiver);
    }

}