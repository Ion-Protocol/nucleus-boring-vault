// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { TellerWithMultiAssetSupport } from "../base/Roles/TellerWithMultiAssetSupport.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Auth, Authority } from "solmate/auth/Auth.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

interface IWHYPE {
    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

contract LoopedHypeDepositor is Auth {
    using SafeTransferLib for ERC20;

    error ZeroAddress();
    error IncorrectNativeDepositAmount();

    IWHYPE constant WHYPE = IWHYPE(0x5555555555555555555555555555555555555555);

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

    constructor(address _teller, address _owner) Auth(_owner, Authority(address(0))) {
        if (_teller == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();

        teller = TellerWithMultiAssetSupport(_teller);
        boringVault = address(teller.vault());

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
        returns (uint256)
    {
        if (msg.value != depositAmount) revert IncorrectNativeDepositAmount();
        WHYPE.deposit{ value: msg.value }();
        return _deposit(ERC20(address(WHYPE)), depositAmount, minimumMint, to, communityCode);
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
        returns (uint256)
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
        bytes32 depositHash = keccak256(abi.encodePacked(address(this), depositNonce++));

        depositAsset.safeApprove(boringVault, depositAmount);

        shares = teller.deposit(depositAsset, depositAmount, minimumMint, to);

        emit DepositWithCommunityCode(
            msg.sender, depositAsset, depositAmount, minimumMint, to, depositHash, communityCode
        );
    }
}
