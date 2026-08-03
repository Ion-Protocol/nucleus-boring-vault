// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IFeeModule, IERC20 } from "src/interfaces/IFeeModule.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

/**
 * @title PaxgDynamicDepositFeeModule
 * @notice Deposit fee module that values PAXG asymmetrically at the vault boundary so that any PAXG:XAU
 * pricing error favors existing shareholders rather than the depositor.
 * @dev The accountant quotes PAXG at its pegged price (1 PAXG = 1 XAU) in both directions. This module
 * charges a deposit fee equal to the shortfall between that peg and PAXG's market value in gold, so the
 * depositor is effectively credited at min(1, p) XAU per PAXG, where p is the market PAXG:XAU rate. When
 * PAXG trades at or above peg (p >= 1) the fee is zero — the pegged valuation already favors the vault.
 *
 * The fee is taken in PAXG (the offer asset). The consuming DistributorCodeDepositor deducts it from the
 * deposit amount before minting and routes it to the fee recipient (the vault), so it accrues to NAV.
 *
 * The immutables bind the module to one vault; this module holds no admin surface. To change any of them,
 * deploy a new module and repoint the depositor via setFeeModule.
 */
contract PaxgDynamicDepositFeeModule is IFeeModule {

    using FixedPointMathLib for uint256;

    /**
     * @notice The pegged PAXG:XAU price of exactly 1, in 18-decimal fixed point (1e18). PAXG is pegged to
     * one troy ounce of gold, so this is both the reference price the fee corrects toward and the
     * denominator of the fee fraction. Matches PAXG's 18 decimals and the oracle's rate precision.
     */
    uint256 public constant PEG_PRICE = 1e18;

    /**
     * @notice Rate provider reporting the market PAXG:XAU rate (XAU per PAXG), in 18-decimal fixed point
     * (PEG_PRICE = 1.0).
     * @dev Reverts on stale feeds, which correctly blocks a deposit priced on stale data.
     */
    IRateProvider public immutable RATE_PROVIDER;

    /**
     * @notice The only deposit asset this module prices. Any other offer asset reverts.
     */
    IERC20 public immutable PAXG;

    /**
     * @notice The vault share token (BoringVault). The order's want asset must equal it, binding the module
     * to the one vault whose accountant pegs PAXG to XAU 1:1. Any other want asset reverts.
     */
    IERC20 public immutable SHARES;

    error ZeroAddress();
    error InvalidOfferAsset(address offerAsset);
    error InvalidWantAsset(address wantAsset);

    /**
     * @notice Initialize the module.
     * @param _oracle PAXG:XAU rate provider (XAU per PAXG, 18-decimal fixed point, PEG_PRICE = 1.0).
     * @param _paxg The PAXG token this module is authorized to price.
     * @param _shares The vault share token (BoringVault) that deposits into this vault mint.
     */
    constructor(IRateProvider _oracle, IERC20 _paxg, IERC20 _shares) {
        if (address(_oracle) == address(0)) revert ZeroAddress();
        if (address(_paxg) == address(0)) revert ZeroAddress();
        if (address(_shares) == address(0)) revert ZeroAddress();
        RATE_PROVIDER = _oracle;
        PAXG = _paxg;
        SHARES = _shares;
    }

    /**
     * @notice Calculate the PAXG-denominated deposit fee for an order.
     * @dev feeAmount = amount * (1 - min(1, p)) where p is the market PAXG:XAU rate. Rounds up so the
     * residual always favors the vault. Reverts if the offer asset is not PAXG, the want asset is not
     * SHARES, or the oracle reports stale data.
     * @param amount PAXG deposit amount.
     * @param offerAsset Must equal PAXG.
     * @param wantAsset Must equal SHARES.
     * @return feeAmount Fee to withhold, denominated in PAXG.
     */
    function calculateOfferFees(
        uint256 amount,
        IERC20 offerAsset,
        IERC20 wantAsset,
        address /* receiver */
    )
        external
        view
        override
        returns (uint256 feeAmount)
    {
        if (address(offerAsset) != address(PAXG)) revert InvalidOfferAsset(address(offerAsset));
        if (address(wantAsset) != address(SHARES)) revert InvalidWantAsset(address(wantAsset));

        // Market PAXG:XAU rate (XAU per PAXG), 18-decimal fixed point. Reverts on stale feeds.
        uint256 price = RATE_PROVIDER.getRate();

        // effectivePrice = min(peg, p): never credit PAXG above peg. When p >= peg the fee fraction is zero.
        uint256 effectivePrice = price < PEG_PRICE ? price : PEG_PRICE;

        // feeFraction = 1 - min(1, p), denominated against the peg. mulDivUp rounds the fee up, in the vault's favor.
        feeAmount = amount.mulDivUp(PEG_PRICE - effectivePrice, PEG_PRICE);
    }

}
