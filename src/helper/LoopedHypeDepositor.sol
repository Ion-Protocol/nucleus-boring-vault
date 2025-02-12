// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { TellerWithMultiAssetSupport } from "../base/Roles/TellerWithMultiAssetSupport.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Auth, Authority } from "solmate/auth/Auth.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

contract LoopedHypeDepositor is Auth {
    using SafeTransferLib for ERC20;

    error ZeroAddress();

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
     * @notice Deposits tokens and emits an event with a unique hash
     * @param depositAsset The ERC20 token to deposit
     * @param depositAmount The amount to deposit
     * @param minimumMint Minimum amount of shares to mint. Reverts otherwise
     * @param to The recipient of the shares
     * @param communityCode Indicator for which operator the token gets staked to
     */
    function depositWithCommunityCode(
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
        bytes32 depositHash = keccak256(abi.encodePacked(address(this), depositNonce++));

        depositAsset.safeTransferFrom(msg.sender, address(this), depositAmount);
        depositAsset.safeApprove(boringVault, depositAmount);

        shares = teller.deposit(depositAsset, depositAmount, minimumMint, to);

        emit DepositWithCommunityCode(
            msg.sender, depositAsset, depositAmount, minimumMint, to, depositHash, communityCode
        );
    }
}
