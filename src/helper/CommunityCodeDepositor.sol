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

    INativeWrapper public immutable NATIVE_WRAPPER;

    TellerWithMultiAssetSupport public immutable teller;
    address public immutable boringVault;
    uint256 public depositNonce;

    // more details on the deposit also exists on the Teller event
    event DepositWithCommunityCode(
        address indexed depositor,
        ERC20 indexed depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        address indexed to,
        bytes32 depositHash,
        bytes communityCode
    );

    constructor(address _teller, address _owner, address _nativeWrapper) Auth(_owner, Authority(address(0))) {
        if (_teller == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();
        if (_nativeWrapper == address(0)) revert ZeroAddress();

        teller = TellerWithMultiAssetSupport(_teller);
        boringVault = address(teller.vault());
        NATIVE_WRAPPER = INativeWrapper(_nativeWrapper);

        if (boringVault == address(0)) revert ZeroAddress();

        // check that if we're depositing native asset, the accountant decimals is equal to base decimals
        if (teller.accountant().decimals() != NATIVE_WRAPPER.decimals()) {
            revert NativeWrapperAccountantDecimalsMismatch();
        }
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
        NATIVE_WRAPPER.deposit{ value: msg.value }();
        return _deposit(ERC20(address(NATIVE_WRAPPER)), depositAmount, minimumMint, to, communityCode);
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
        if (to == address(0)) revert ZeroAddress();

        bytes32 depositHash = keccak256(abi.encodePacked(address(this), ++depositNonce));

        depositAsset.safeApprove(boringVault, depositAmount);

        shares = teller.deposit(depositAsset, depositAmount, minimumMint);
        ERC20(boringVault).safeTransfer(to, shares);

        emit DepositWithCommunityCode(
            msg.sender, depositAsset, depositAmount, minimumMint, to, depositHash, communityCode
        );
    }
}
