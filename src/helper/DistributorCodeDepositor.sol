// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { TellerWithMultiAssetSupport } from "../base/Roles/TellerWithMultiAssetSupport.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Auth, Authority } from "solmate/auth/Auth.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

interface INativeWrapper {

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function deposit() external payable;

    function withdraw(uint256 wad) external;

    function decimals() external view returns (uint8);

}

contract DistributorCodeDepositor is Auth {

    using SafeTransferLib for ERC20;

    error ZeroAddress();
    error IncorrectNativeDepositAmount();
    error NativeWrapperAccountantDecimalsMismatch();
    error NativeDepositNotSupported();
    error PermitFailedAndAllowanceTooLow();

    INativeWrapper public immutable nativeWrapper;

    TellerWithMultiAssetSupport public immutable teller;
    address public immutable boringVault;
    bool public immutable isNativeDepositSupported;

    uint256 public depositNonce;

    // more details on the deposit also exists on the Teller event
    event DepositWithDistributorCode(
        address indexed depositor,
        ERC20 indexed depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address to,
        bytes32 depositHash,
        bytes indexed distributorCode
    );

    constructor(
        TellerWithMultiAssetSupport _teller,
        INativeWrapper _nativeWrapper,
        Authority _rolesAuthority,
        bool _isNativeDepositSupported,
        address _owner
    )
        Auth(_owner, _rolesAuthority)
    {
        if (address(_teller) == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();

        // check that if we're depositing native asset, the accountant decimals is equal to base decimals
        if (_isNativeDepositSupported) {
            if (address(_nativeWrapper) == address(0)) revert ZeroAddress();
            if (_teller.accountant().decimals() != _nativeWrapper.decimals()) {
                revert NativeWrapperAccountantDecimalsMismatch();
            }
        } else {
            if (address(_nativeWrapper) != address(0)) {
                if (_teller.accountant().decimals() != _nativeWrapper.decimals()) {
                    revert NativeWrapperAccountantDecimalsMismatch();
                }
            }
        }

        teller = _teller;
        boringVault = address(_teller.vault());
        nativeWrapper = _nativeWrapper;
        isNativeDepositSupported = _isNativeDepositSupported;

        if (boringVault == address(0)) revert ZeroAddress();
    }

    /**
     * @notice For depositing the native asset of the chain
     * @param depositAmount The amount to deposit
     * @param minimumMint Minimum amount of shares to mint. Reverts otherwise
     * @param to The recipient of the shares
     * @param distributorCode Indicator for which operator the token gets staked to
     */
    function depositNative(
        uint256 depositAmount,
        uint256 minimumMint,
        address to,
        bytes calldata distributorCode
    )
        external
        payable
        requiresAuth
        returns (uint256 shares)
    {
        if (!isNativeDepositSupported) revert NativeDepositNotSupported();
        if (msg.value != depositAmount) revert IncorrectNativeDepositAmount();
        nativeWrapper.deposit{ value: msg.value }();
        return _deposit(ERC20(address(nativeWrapper)), depositAmount, minimumMint, to, distributorCode);
    }

    /**
     * @notice Deposits tokens and emits an event with a unique hash
     * @param depositAsset The ERC20 token to deposit
     * @param depositAmount The amount to deposit
     * @param minimumMint Minimum amount of shares to mint. Reverts otherwise
     * @param to The recipient of the shares
     * @param distributorCode Indicator for which operator the token gets staked to
     */
    function deposit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address to,
        bytes calldata distributorCode
    )
        external
        requiresAuth
        returns (uint256 shares)
    {
        depositAsset.safeTransferFrom(msg.sender, address(this), depositAmount);
        return _deposit(depositAsset, depositAmount, minimumMint, to, distributorCode);
    }

    function depositWithPermit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address to,
        bytes calldata distributorCode,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        requiresAuth
        returns (uint256 shares)
    {
        // cannot just wrap the teller.depositWithPermit because
        // we need to use permit to process approval on this contract before making a deposit.

        // solhint-disable-next-line no-empty-blocks
        try depositAsset.permit(msg.sender, address(this), depositAmount, deadline, v, r, s) { }
        catch {
            if (depositAsset.allowance(msg.sender, address(this)) < depositAmount) {
                revert PermitFailedAndAllowanceTooLow();
            }
        }

        depositAsset.safeTransferFrom(msg.sender, address(this), depositAmount);

        return _deposit(depositAsset, depositAmount, minimumMint, to, distributorCode);
    }

    /**
     * Always assumes that the `depositAsset` is on this contract's balance.
     */
    function _deposit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address to,
        bytes calldata distributorCode
    )
        internal
        returns (uint256 shares)
    {
        if (to == address(0)) revert ZeroAddress();
        bytes32 depositHash;
        unchecked {
            depositHash = keccak256(abi.encodePacked(address(this), ++depositNonce, block.chainid));
        }

        // Clear leftover allowance for non-standard ERC20
        _tryClearApproval(depositAsset);
        depositAsset.safeApprove(boringVault, depositAmount);

        shares = teller.deposit(depositAsset, depositAmount, minimumMint);
        ERC20(boringVault).safeTransfer(to, shares);
        // Clear leftover allowance
        _tryClearApproval(depositAsset);

        emit DepositWithDistributorCode(
            msg.sender, depositAsset, depositAmount, minimumMint, to, depositHash, distributorCode
        );
    }

    /**
     * @notice Helper function to clear allowance. Helps with weird ERC20s that require a 0 approval before a new one.
     * And also this does not revert on failure in order to also handle ERC20s that revert on a zero approval.
     * @dev In the case of a token that reverts on a zero approval AND requires approval set to 0 before a new approval
     * this will of course fail. But we would consider this a critical flaw of the token itself.
     */
    function _tryClearApproval(ERC20 depositAsset) internal {
        address(depositAsset).call(abi.encodeWithSelector(depositAsset.approve.selector, boringVault, 0));
    }

}
