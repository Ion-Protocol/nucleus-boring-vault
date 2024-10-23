// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { BoringVault } from "../base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "../base/Roles/TellerWithMultiAssetSupport.sol";

interface WarpRoute {
    function transferRemote(uint32 _destination, bytes32 _recipient, uint256 _amountOrId) external returns (bytes32);
}

/**
 * @notice A simple wrapper to call both `deposit` on a Teller and
 * `transferRemote` on a WarpRoute in one transaction. This contract can only be
 * used with a defined Teller. If a new Teller is deployed, a new Wrapper must
 * be deployed.
 */
contract WarpRouteWrapper {
    using SafeTransferLib for ERC20;

    BoringVault public boringVault;
    TellerWithMultiAssetSupport public teller;
    WarpRoute public warpRoute;

    constructor(TellerWithMultiAssetSupport _teller, WarpRoute _warpRoute) {
        teller = _teller;
        warpRoute = _warpRoute;
        boringVault = _teller.vault();

        // Infinite approvals to the warpRoute okay because this contract will
        // never hold any balance aside from donations.
        boringVault.approve(address(warpRoute), type(uint256).max);
    }

    /**
     * @dev There's two sets of approvals this contract needs to grant. It needs
     * to approve the BoringVault to take its `depositAsset`, and it needs to
     * approve the WarpRoute to take the BoringVault shares. The latter is done
     * in the constructor.
     *
     * NOTE that the `depositAsset` can vary as the Teller can add new supported
     * assets.
     */
    function depositAndBridge(
        ERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint,
        uint32 _destination,
        bytes32 _recipient
    )
        external
        returns (uint256 sharesMinted, bytes32 messageId)
    {
        depositAsset.safeTransferFrom(msg.sender, address(this), depositAmount);

        if (depositAsset.allowance(address(this), address(boringVault)) < depositAmount) {
            depositAsset.approve(address(boringVault), type(uint256).max);
        }

        sharesMinted = teller.deposit(depositAsset, depositAmount, minimumMint);

        messageId = warpRoute.transferRemote(_destination, _recipient, sharesMinted);
    }
}
