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

contract CommunityCodeDepositor is Auth {

    using SafeTransferLib for ERC20;

    error ZeroAddress();
    error IncorrectNativeDepositAmount();
    error NativeWrapperAccountantDecimalsMismatch();

    INativeWrapper public immutable nativeWrapper;

    TellerWithMultiAssetSupport public immutable teller;
    address public immutable boringVault;
    uint256 public depositNonce;

    // more details on the deposit also exists on the Teller event
    event DepositWithCommunityCode(
        address indexed depositor,
        ERC20 indexed depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address to,
        bytes32 depositHash,
        bytes indexed communityCode
    );

    constructor(
        TellerWithMultiAssetSupport _teller,
        INativeWrapper _nativeWrapper,
        address _owner
    )
        Auth(_owner, Authority(address(0)))
    {
        if (address(_teller) == address(0)) revert ZeroAddress();
        // if (address(_nativeWrapper) == address(0)) revert ZeroAddress();

        if (_owner == address(0)) revert ZeroAddress();

        // check that if we're depositing native asset, the accountant decimals is equal to base decimals
        if (address(_nativeWrapper) != address(0)) {
            if (_teller.accountant().decimals() != _nativeWrapper.decimals()) {
                revert NativeWrapperAccountantDecimalsMismatch();
            }
        }

        teller = _teller;
        boringVault = address(_teller.vault());
        nativeWrapper = _nativeWrapper;

        if (boringVault == address(0)) revert ZeroAddress();
    }

    /**
     * @notice For depositing the native asset of the chain
     * @param depositAmount The amount to deposit
     * @param minimumMint Minimum amount of shares to mint. Reverts otherwise
     * @param to The recipient of the shares
     * @param communityCode Indicator for which operator the token gets staked to
     */
    function depositNative(
        uint256 depositAmount,
        uint256 minimumMint,
        address to,
        bytes calldata communityCode
    )
        external
        payable
        requiresAuth
        returns (uint256 shares)
    {
        if (msg.value != depositAmount) revert IncorrectNativeDepositAmount();
        nativeWrapper.deposit{ value: msg.value }();
        return _deposit(ERC20(address(nativeWrapper)), depositAmount, minimumMint, to, communityCode);
    }

    /**
     * @notice Deposits tokens and emits an event with a unique hash
     * @param depositAsset The ERC20 token to deposit
     * @param depositAmount The amount to deposit
     * @param minimumMint Minimum amount of shares to mint. Reverts otherwise
     * @param to The recipient of the shares
     * @param communityCode Indicator for which operator the token gets staked to
     */
    function deposit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address to,
        bytes calldata communityCode
    )
        external
        requiresAuth
        returns (uint256 shares)
    {
        depositAsset.safeTransferFrom(msg.sender, address(this), depositAmount);
        return _deposit(depositAsset, depositAmount, minimumMint, to, communityCode);
    }

    function depositWithPermit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address to,
        bytes calldata communityCode,
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
        depositAsset.permit(msg.sender, address(this), depositAmount, deadline, v, r, s);

        depositAsset.safeTransferFrom(msg.sender, address(this), depositAmount);

        return _deposit(depositAsset, depositAmount, minimumMint, to, communityCode);
    }

    /**
     * Always assumes that the `depositAsset` is on this contract's balance.
     */
    function _deposit(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address to,
        bytes calldata communityCode
    )
        internal
        returns (uint256 shares)
    {
        bytes32 depositHash = keccak256(abi.encodePacked(address(this), depositNonce++));

        depositAsset.safeApprove(boringVault, depositAmount);

        // TODO: THIS MUST BE TRANSFERRED OUT
        shares = teller.deposit(depositAsset, depositAmount, minimumMint);
        ERC20(boringVault).safeTransfer(to, shares);

        emit DepositWithCommunityCode(
            msg.sender, depositAsset, depositAmount, minimumMint, to, depositHash, communityCode
        );
    }

}
