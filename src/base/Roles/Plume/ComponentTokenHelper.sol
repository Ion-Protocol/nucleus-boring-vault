// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IComponentToken } from "./IComponentToken.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

/**
 * @title ComponentTokenHelper
 * @notice Abstract contract that implements in the `ComponentToken` interface
 * @dev This is used to make contracts compliant to the `ComponentToken` interface.
 */
abstract contract ComponentTokenHelper is IComponentToken {
    using FixedPointMathLib for uint256;

    // Errors
    error Unimplemented();

    /**
     * @notice Transfer assets from the owner into the vault and submit a request to buy shares
     * @param assets Amount of `asset` to deposit
     * @param controller Controller of the request
     * @param owner Source of the assets to deposit
     * @return requestId Discriminator between non-fungible requests
     */
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    )
        public
        virtual
        returns (uint256 requestId)
    {
        revert Unimplemented();
    }

    /**
     * @notice Fulfill a request to buy shares by minting shares to the receiver
     * @param assets Amount of `asset` that was deposited by `requestDeposit`
     * @param receiver Address to receive the shares
     * @param controller Controller of the request
     */
    function deposit(uint256 assets, address receiver, address controller) public virtual returns (uint256 shares) {
        revert Unimplemented();
    }

    /**
     * @notice Transfer shares from the owner into the vault and submit a request to redeem assets
     * @param shares Amount of shares to redeem
     * @param controller Controller of the request
     * @param owner Source of the shares to redeem
     * @return requestId Discriminator between non-fungible requests
     */
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    )
        public
        virtual
        returns (uint256 requestId)
    {
        revert Unimplemented();
    }

    /**
     * @notice Fulfill a request to redeem assets by transferring assets to the receiver
     * @param shares Amount of shares that was redeemed by `requestRedeem`
     * @param receiver Address to receive the assets
     * @param controller Controller of the request
     */
    function redeem(uint256 shares, address receiver, address controller) public virtual returns (uint256 assets) {
        // Redeem doesn't do anything anymore because as soon as the AtomicQueue
        // request is processed, the msg.sender will receive their this.asset
        revert Unimplemented();
    }

    // Getter View Functions

    function totalSupply() public view virtual returns (uint256 totalSupply) {
        revert Unimplemented();
    }

    function balanceOf(address owner) public view virtual returns (uint256 balance) {
        revert Unimplemented();
    }

    /**
     * @notice Total value held in the vault
     * @dev Example ERC20 implementation: return convertToAssets(totalSupply())
     */
    function totalAssets() public view virtual returns (uint256 totalManagedAssets) {
        revert Unimplemented();
    }

    /**
     * @notice Total value held by the given owner
     * @dev Example ERC20 implementation: return convertToAssets(balanceOf(owner))
     * @param owner Address to query the balance of
     * @return assets Total value held by the owner
     */
    function assetsOf(address owner) public view virtual returns (uint256 assets) {
        revert Unimplemented();
    }

    function convertToShares(uint256 assets) public view virtual returns (uint256 shares) {
        revert Unimplemented();
    }

    // returns quote / share in quote decimals
    function convertToAssets(uint256 shares) public view virtual returns (uint256 assets) {
        revert Unimplemented();
    }

    /**
     * @notice Total amount of assets sent to the vault as part of pending deposit requests
     * @param requestId Discriminator between non-fungible requests
     * @param controller Controller of the requests
     * @return assets Amount of pending deposit assets for the given requestId and controller
     */
    function pendingDepositRequest(uint256 requestId, address controller) public pure returns (uint256 assets) {
        revert Unimplemented();
    }

    /**
     * @notice Total amount of assets sitting in the vault as part of claimable deposit requests
     * @param requestId Discriminator between non-fungible requests
     * @param controller Controller of the requests
     * @return assets Amount of claimable deposit assets for the given requestId and controller
     */
    function claimableDepositRequest(uint256 requestId, address controller) public pure returns (uint256 assets) {
        revert Unimplemented();
    }

    /**
     * @notice Total amount of shares sent to the vault as part of pending redeem requests
     * @param requestId Discriminator between non-fungible requests
     * @param controller Controller of the requests
     * @return shares Amount of pending redeem shares for the given requestId and controller
     */
    function pendingRedeemRequest(uint256 requestId, address controller) public pure returns (uint256 shares) {
        revert Unimplemented();
    }

    /**
     * @notice Total amount of assets sitting in the vault as part of claimable redeem requests
     * @param requestId Discriminator between non-fungible requests
     * @param controller Controller of the requests
     * @return shares Amount of claimable redeem shares for the given requestId and controller
     */
    function claimableRedeemRequest(uint256 requestId, address controller) public pure returns (uint256 shares) {
        revert Unimplemented();
    }
}
