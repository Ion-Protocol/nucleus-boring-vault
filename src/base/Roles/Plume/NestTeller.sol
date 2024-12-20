// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { ComponentTokenHelper } from "./ComponentTokenHelper.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { MultiChainLayerZeroTellerWithMultiAssetSupport } from
    "src/base/Roles/CrossChain/MultiChainLayerZeroTellerWithMultiAssetSupport.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
/**
 * @title NestTeller
 * @notice Teller implementation for the Nest vault
 * @dev A Teller that only allows deposits of a single `asset` configured in this contract.
 * configured.
 */

contract NestTeller is ComponentTokenHelper, MultiChainLayerZeroTellerWithMultiAssetSupport {
    using FixedPointMathLib for uint256;

    // Errors
    error InvalidController();
    error InvalidReceiver();

    // Public State

    uint256 public minimumMintPercentage = 10_000; // Must be 4 decimals i.e. 9999 = 99.99%

    address public asset; // The asset that can be deposited through the ComponentToken `deposit` function.

    constructor(
        address _owner,
        address _vault,
        address _accountant,
        address _endpoint,
        address _asset,
        uint256 _minimumMintPercentage
    )
        MultiChainLayerZeroTellerWithMultiAssetSupport(_owner, _vault, _accountant, _endpoint)
    {
        asset = _asset;
        minimumMintPercentage = _minimumMintPercentage;
    }

    // Admin Setters

    function setAsset(address _asset) external requiresAuth {
        asset = _asset;
    }

    function setMinimumMintPercentage(uint256 _minimumMintPercentage) external requiresAuth {
        minimumMintPercentage = _minimumMintPercentage;
    }

    /**
     * @notice Fulfill a request to buy shares by minting shares to the receiver
     * @param assets Amount of `asset` that was deposited by `requestDeposit`
     * @param receiver Address to receive the shares
     * @param controller Controller of the request
     */
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    )
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        // Ensure receiver is msg.sender
        if (receiver != msg.sender) {
            revert InvalidReceiver();
        }
        if (controller != msg.sender) {
            revert InvalidController();
        }

        return deposit(ERC20(asset), assets, assets.mulDivDown(minimumMintPercentage, 10_000));
    }

    // Getter View Functions

    function totalSupply() public view override returns (uint256 totalSupply) {
        return vault.totalSupply();
    }

    function balanceOf(address owner) public view override returns (uint256 balance) {
        return vault.balanceOf(owner);
    }

    /**
     * @notice Total value held in the vault
     * @dev Example ERC20 implementation: return convertToAssets(totalSupply())
     */
    function totalAssets() public view override returns (uint256 totalManagedAssets) {
        return convertToAssets(vault.totalSupply());
    }

    /**
     * @notice Total value held by the given owner
     * @dev Example ERC20 implementation: return convertToAssets(balanceOf(owner))
     * @param owner Address to query the balance of
     * @return assets Total value held by the owner
     */
    function assetsOf(address owner) public view override returns (uint256 assets) {
        return convertToAssets(vault.balanceOf(owner));
    }

    function convertToShares(uint256 assets) public view override returns (uint256 shares) {
        return assets.mulDivDown(10 ** vault.decimals(), accountant.getRateInQuote(ERC20(asset)));
    }

    function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
        return shares.mulDivDown(accountant.getRateInQuote(ERC20(asset)), 10 ** vault.decimals());
    }
}
