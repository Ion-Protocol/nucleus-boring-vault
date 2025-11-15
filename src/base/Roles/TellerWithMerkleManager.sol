// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";

/**
 * @title TellerWithMerkleManager
 * @notice This contract takes on a strategist role that is able to call
 *         ManagerWithMerkleVerification.
 * @notice In order for a deposit to trigger the strategist call, it needs a signed
 *         payload of the manageWithMerkleVerification parameter approved by a
 *         whitelisted approver.
 * @notice The "approver" will send a signed payload with the following parameters:
 *         - target contract, the function parameters, and whether to send native ether or not.
 * @notice Then, upon calling the deposit function, we want to use these parameters to
 *         make a manage call.
 * @notice An invariant should be that no manage call consisting of target contract and function parameters should be
 * able to be called, unless it's been signed by the approver.
 * @custom:security-contact security@molecularlabs.io
 */
contract TellerWithMerkleManager is TellerWithMultiAssetSupport {

    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ========================================= STATE =========================================

    /**
     * @notice Mapping of approver addresses to their whitelist status.
     */
    mapping(address => bool) public isApprover;

    /**
     * @notice The ManagerWithMerkleVerification contract this teller uses.
     */
    ManagerWithMerkleVerification public immutable manager;

    /**
     * @notice Nonce used to prevent signature replay attacks.
     */
    uint256 public signatureNonce;

    /**
     * @notice Mapping of used signature hashes to prevent replay attacks.
     */
    mapping(bytes32 => bool) public usedSignatures;

    // ========================================= ERRORS =========================================

    error TellerWithMerkleManager__NotApprover();
    error TellerWithMerkleManager__SignatureAlreadyUsed();
    error TellerWithMerkleManager__InvalidArrayLengths();

    // ========================================= EVENTS =========================================

    event ApproverAdded(address indexed approver);
    event ApproverRemoved(address indexed approver);
    event DepositWithManageCall(
        address indexed user,
        address indexed depositAsset,
        uint256 depositAmount,
        uint256 shares,
        uint256 signatureNonce
    );

    // ========================================= CONSTRUCTOR =========================================

    constructor(
        address _owner,
        address _vault,
        address _accountant,
        address _manager
    )
        TellerWithMultiAssetSupport(_owner, _vault, _accountant)
    {
        manager = ManagerWithMerkleVerification(_manager);
    }

    // ========================================= ADMIN FUNCTIONS =========================================

    /**
     * @notice Adds an approver to the whitelist.
     * @dev Callable by OWNER_ROLE.
     */
    function addApprover(address approver) external requiresAuth {
        isApprover[approver] = true;
        emit ApproverAdded(approver);
    }

    /**
     * @notice Removes an approver from the whitelist.
     * @dev Callable by OWNER_ROLE.
     */
    function removeApprover(address approver) external requiresAuth {
        isApprover[approver] = false;
        emit ApproverRemoved(approver);
    }

    // ========================================= USER FUNCTIONS =========================================

    /**
     * @notice Allows users to deposit into the BoringVault and trigger a strategist manage call
     *         with signed parameters from a whitelisted approver.
     * @param depositAsset The asset to deposit.
     * @param depositAmount The amount to deposit.
     * @param minimumMint The minimum shares to receive.
     * @param manageProofs The merkle proofs for the manage call.
     * @param decodersAndSanitizers The decoder and sanitizer addresses for the manage call.
     * @param targets The target addresses for the manage call.
     * @param targetData The calldata for the manage call.
     * @param values The native ETH values for the manage call.
     * @param signature The signature from the approver.
     * @return shares The shares minted.
     */
    function depositWithManageCall(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        bytes32[][] calldata manageProofs,
        address[] calldata decodersAndSanitizers,
        address[] calldata targets,
        bytes[] calldata targetData,
        uint256[] calldata values,
        bytes calldata signature
    )
        external
        requiresAuth
        nonReentrant
        returns (uint256 shares)
    {
        if (isPaused) revert TellerWithMultiAssetSupport__Paused();
        if (!isSupported[depositAsset]) revert TellerWithMultiAssetSupport__AssetNotSupported();

        // Verify array lengths match
        uint256 targetsLength = targets.length;
        if (targetsLength != manageProofs.length) revert TellerWithMerkleManager__InvalidArrayLengths();
        if (targetsLength != targetData.length) revert TellerWithMerkleManager__InvalidArrayLengths();
        if (targetsLength != values.length) revert TellerWithMerkleManager__InvalidArrayLengths();
        if (targetsLength != decodersAndSanitizers.length) revert TellerWithMerkleManager__InvalidArrayLengths();

        // Create the message hash that should be signed
        // NOTE: The approver signs this message OFF-CHAIN with their private key.
        // The signature is then passed to this function as a parameter.
        // We recreate the same message hash here to verify the signature.
        bytes32 messageHash = keccak256(
            abi.encode(
                address(this),
                block.chainid,
                signatureNonce,
                manageProofs,
                decodersAndSanitizers,
                targets,
                targetData,
                values
            )
        );

        // Format for EIP-191 personal sign (adds "\x19Ethereum Signed Message:\n32" prefix)
        // This matches what wallets like MetaMask do when signing messages
        bytes32 digest = messageHash.toEthSignedMessageHash();

        // Recover the signer's address from the signature using ECDSA
        // ECDSA.recover uses mathematical properties of elliptic curves to extract
        // the public key (and thus address) that created the signature
        // If the signature doesn't match the digest, this will return an invalid address
        address recoveredSigner = digest.recover(signature);
        if (!isApprover[recoveredSigner]) revert TellerWithMerkleManager__NotApprover();

        // Check for replay attacks
        bytes32 signatureHash = keccak256(signature);
        if (usedSignatures[signatureHash]) revert TellerWithMerkleManager__SignatureAlreadyUsed();
        usedSignatures[signatureHash] = true;

        // Perform the deposit
        shares = _erc20Deposit(depositAsset, depositAmount, minimumMint, msg.sender);
        _afterPublicDeposit(msg.sender, depositAsset, depositAmount, shares, shareLockPeriod);

        // Make the manage call as this contract (which should have STRATEGIST_ROLE on the manager)
        // If this fails, the entire transaction reverts including the deposit
        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);

        // Increment nonce for next signature (only after everything succeeds)
        uint256 currentNonce = signatureNonce;
        signatureNonce++;

        emit DepositWithManageCall(msg.sender, address(depositAsset), depositAmount, shares, currentNonce);
    }

}
