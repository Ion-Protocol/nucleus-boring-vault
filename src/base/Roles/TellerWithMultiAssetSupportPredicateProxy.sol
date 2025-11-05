// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";
import { PredicateClient } from "@predicate/src/mixins/PredicateClient.sol";
import { PredicateMessage } from "@predicate/src/interfaces/IPredicateClient.sol";
import { IPredicateManager } from "@predicate/src/interfaces/IPredicateManager.sol";
import { BridgeData, CrossChainTellerBase } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";

/**
 * @title TellerWithMultiAssetSupportPredicateProxy
 * @custom:security-contact security@molecularlabs.io
 */
contract TellerWithMultiAssetSupportPredicateProxy is Ownable, ReentrancyGuard, PredicateClient, Pausable {

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    //============================== ERRORS ===============================

    error TellerWithMultiAssetSupportPredicateProxy__PredicateUnauthorizedTransaction();
    error TellerWithMultiAssetSupportPredicateProxy__Paused();
    error TellerWithMultiAssetSupportPredicateProxy__ETHTransferFailed();

    event Deposit(
        address indexed teller,
        address indexed receiver,
        address indexed depositAsset,
        uint256 depositAmount,
        uint256 shareAmount,
        uint256 depositTimestamp,
        uint256 shareLockPeriodAtTimeOfDeposit,
        uint256 nonce,
        address vault
    );

    //============================== IMMUTABLES ===============================

    /**
     * @notice Stores the last sender who called the contract
     * This is used to route refunds to the correct user on deposit and bridge
     */
    address private lastSender;

    constructor(address _owner, address _serviceManager, string memory _policyID) Ownable(_owner) {
        _initPredicateClient(_serviceManager, _policyID);
    }

    // ========================================= USER FUNCTIONS =========================================

    /**
     * @notice Allows users to deposit into the BoringVault, if the teller contract is not paused.
     * @dev Publicly callable. Uses the predicate authorization pattern to validate the transaction
     * @param depositAsset ERC20 to deposit
     * @param depositAmount Amount of deposit asset to deposit
     * @param minimumMint Minimum required shares to receive
     * @param recipient Address which to forward shares
     * @param teller CrossChainTellerBase contract to deposit into
     * @param predicateMessage Predicate message to authorize the transaction
     */
    function deposit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address recipient,
        CrossChainTellerBase teller,
        PredicateMessage calldata predicateMessage
    )
        external
        nonReentrant
        returns (uint256 shares)
    {
        if (paused()) {
            revert TellerWithMultiAssetSupportPredicateProxy__Paused();
        }

        //@dev This is NOT the actual function that is called, it is the against which the predicate is authorized
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("deposit()");
        if (!_authorizeTransaction(predicateMessage, encodedSigAndArgs, msg.sender, 0)) {
            revert TellerWithMultiAssetSupportPredicateProxy__PredicateUnauthorizedTransaction();
        }
        ERC20 vault = ERC20(teller.vault());
        //approve vault to take assets from proxy
        depositAsset.safeApprove(address(vault), depositAmount);
        //transfer deposit assets from sender to this contract
        depositAsset.safeTransferFrom(msg.sender, address(this), depositAmount);
        // mint shares
        shares = teller.deposit(depositAsset, depositAmount, minimumMint);
        vault.safeTransfer(recipient, shares);
        uint96 nonce = teller.depositNonce();
        //get the current share lock period
        uint64 currentShareLockPeriod = teller.shareLockPeriod();
        emit Deposit(
            address(teller),
            msg.sender,
            address(depositAsset),
            depositAmount,
            shares,
            block.timestamp,
            currentShareLockPeriod,
            nonce > 0 ? nonce - 1 : 0,
            address(vault)
        );
    }

    /**
     * @notice function to deposit into the vault AND bridge crosschain in 1 call
     * @dev Uses the predicate authorization pattern to validate the transaction
     * @param depositAsset ERC20 to deposit
     * @param depositAmount amount of deposit asset to deposit
     * @param minimumMint minimum required shares to receive
     * @param teller CrossChainTellerBase contract to deposit into
     * @param data Bridge Data
     * @param predicateMessage Predicate message to authorize the transaction
     */
    function depositAndBridge(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        BridgeData calldata data,
        CrossChainTellerBase teller,
        PredicateMessage calldata predicateMessage
    )
        external
        payable
        nonReentrant
    {
        if (paused()) {
            revert TellerWithMultiAssetSupportPredicateProxy__Paused();
        }

        //@dev This is NOT the actual function that is called, it is the against which the predicate is authorized
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("depositAndBridge()");
        //still use 0 for msg.value since we only need validation against sender address
        if (!_authorizeTransaction(predicateMessage, encodedSigAndArgs, msg.sender, 0)) {
            revert TellerWithMultiAssetSupportPredicateProxy__PredicateUnauthorizedTransaction();
        }
        lastSender = msg.sender;
        ERC20 vault = ERC20(teller.vault());
        //approve vault to take assets from proxy
        depositAsset.safeApprove(address(vault), depositAmount);
        //transfer deposit assets from sender to this contract
        depositAsset.safeTransferFrom(msg.sender, address(this), depositAmount);
        // mint shares
        teller.depositAndBridge{ value: msg.value }(depositAsset, depositAmount, minimumMint, data);
        lastSender = address(0);
        uint96 nonce = teller.depositNonce();
        //get the current share lock period
        uint64 currentShareLockPeriod = teller.shareLockPeriod();
        AccountantWithRateProviders accountant = AccountantWithRateProviders(teller.accountant());
        //get the share amount
        uint256 shares = depositAmount.mulDivDown(10 ** vault.decimals(), accountant.getRateInQuoteSafe(depositAsset));

        emit Deposit(
            address(teller),
            data.destinationChainReceiver,
            address(depositAsset),
            depositAmount,
            shares,
            block.timestamp,
            currentShareLockPeriod,
            nonce > 0 ? nonce - 1 : 0,
            address(vault)
        );
    }

    /**
     * @notice Function to check if the user is authorized to call the predicate
     * @dev This is NOT an actual function that is called, it serves as a function to allow any contract to check a user
     * against the predicate
     * @param user address of the user
     * @param predicateMessage Predicate message to authorize the transaction
     */
    function genericUserCheckPredicate(
        address user,
        PredicateMessage calldata predicateMessage
    )
        external
        returns (bool)
    {
        //@dev This is NOT an actual function that is called, it is the against which the predicate is authorized
        bytes memory encodedSigAndArgs = abi.encodeWithSignature("accessCheck(address)", user);
        //still use 0 for msg.value since we only need validation against sender and user address
        if (!_authorizeTransaction(predicateMessage, encodedSigAndArgs, msg.sender, 0)) {
            return false;
        }
        return true;
    }

    /**
     * @notice Updates the policy ID
     * @param _policyID policy ID from onchain
     */
    function setPolicy(string memory _policyID) external onlyOwner {
        _setPolicy(_policyID);
    }

    /**
     * @notice Function for setting the ServiceManager
     * @param _predicateManager address of the service manager
     */
    function setPredicateManager(address _predicateManager) public onlyOwner {
        _setPredicateManager(_predicateManager);
    }

    /**
     * @notice Allows the contract to receive ETH refunds and forwards them to the original sender
     */
    receive() external payable {
        // If we have a lastSender and receive ETH, forward it
        if (lastSender != address(0) && msg.value > 0) {
            // Forward the ETH to the last sender
            (bool success,) = lastSender.call{ value: msg.value }("");
            if (!success) revert TellerWithMultiAssetSupportPredicateProxy__ETHTransferFailed();
        }
    }

}
