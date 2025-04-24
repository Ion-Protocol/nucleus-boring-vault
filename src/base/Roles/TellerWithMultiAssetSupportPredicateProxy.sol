// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { WETH } from "@solmate/tokens/WETH.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";
import { PredicateClient } from "@predicate/src/mixins/PredicateClient.sol";
import { PredicateMessage } from "@predicate/src/interfaces/IPredicateClient.sol";
import { IPredicateManager } from "@predicate/src/interfaces/IPredicateManager.sol";
import { MultiChainTellerBase } from "src/base/Roles/CrossChain/MultiChainTellerBase.sol";
import { BridgeData, CrossChainTellerBase } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";

/**
 * @title PredicateTellerProxy
 * @custom:security-contact security@molecularlabs.io
 */
contract TellerWithMultiAssetSupportPredicateProxy is Auth, ReentrancyGuard, PredicateClient {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for WETH;

    //============================== ERRORS ===============================

    error TellerWithMultiAssetSupportPredicateProxy__PredicateUnauthorizedTransaction();
    error TellerWithMultiAssetSupportPredicateProxy__NoRefundedShares(bytes32 msgId);

    //============================== IMMUTABLES ===============================

    /**
     * @notice The Teller this contract is working with.
     */
    CrossChainTellerBase public immutable teller;
    // could change to have mapping to share among tellers, but this is PoC

    constructor(
        address _owner,
        address _teller,
        address _serviceManager,
        string memory _policyID
    )
        Auth(_owner, Authority(address(0)))
    {
        teller = MultiChainTellerBase(payable(_teller));
        _initPredicateClient(_serviceManager, _policyID);
    }

    // ========================================= USER FUNCTIONS =========================================

    /**
     * @notice Allows users to deposit into the BoringVault, if this contract is not paused.
     * @dev Publicly callable. Uses the predicate authorization pattern to validate the transaction
     * @param depositAsset ERC20 to deposit
     * @param depositAmount Amount of deposit asset to deposit
     * @param minimumMint Minimum required shares to receive
     * @param recipient Address which to forward shares
     * @param predicateMessage Predicate message to authorize the transaction
     */
    function deposit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address recipient,
        PredicateMessage calldata predicateMessage
    )
        external
        requiresAuth
        nonReentrant
        returns (uint256 shares)
    {
        //authorization would be very similar to other flows
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("_deposit()");
        if (!_authorizeTransaction(predicateMessage, encodedSigAndArgs, msg.sender, 0)) {
            revert TellerWithMultiAssetSupportPredicateProxy__PredicateUnauthorizedTransaction();
        }
        ERC20 vault = ERC20(teller.vault());
        //approve vault to take assets from proxy
        depositAsset.approve(address(vault), depositAmount);
        //transfer deposit assets from sender to this contract
        depositAsset.transferFrom(msg.sender, address(this), depositAmount);
        // mint shares
        shares = teller.deposit(depositAsset, depositAmount, minimumMint);
        vault.transfer(recipient, shares);
        //possibly add extra event
    }

    /**
     * @notice function to deposit into the vault AND bridge crosschain in 1 call
     * @dev Uses the predicate authorization pattern to validate the transaction
     * @param depositAsset ERC20 to deposit
     * @param depositAmount amount of deposit asset to deposit
     * @param minimumMint minimum required shares to receive
     * @param data Bridge Data
     * @param predicateMessage Predicate message to authorize the transaction
     */
    function depositAndBridge(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        BridgeData calldata data,
        PredicateMessage calldata predicateMessage
    )
        external
        payable
        requiresAuth
        nonReentrant
    {
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("_depositAndBridge()");
        if (!_authorizeTransaction(predicateMessage, encodedSigAndArgs, msg.sender, 0)) {
            revert TellerWithMultiAssetSupportPredicateProxy__PredicateUnauthorizedTransaction();
        }
        ERC20 vault = ERC20(teller.vault());
        //approve vault to take assets from proxy
        depositAsset.approve(address(vault), depositAmount);
        //transfer deposit assets from sender to this contract
        depositAsset.transferFrom(msg.sender, address(this), depositAmount);
        // mint shares
        teller.depositAndBridge(depositAsset, depositAmount, minimumMint, data);
    }

    /**
     * @notice Updates the policy ID
     * @param _policyID policy ID from onchain
     */
    function setPolicy(string memory _policyID) external requiresAuth {
        _setPolicy(_policyID);
    }

    /**
     * @notice Function for setting the ServiceManager
     * @param _predicateManager address of the service manager
     */
    function setPredicateManager(address _predicateManager) public requiresAuth {
        _setPredicateManager(_predicateManager);
    }
}
