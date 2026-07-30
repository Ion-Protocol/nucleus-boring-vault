// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IFeeModule, IERC20 } from "src/interfaces/IFeeModule.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

/**
 * @title PaxgDynamicWithdrawFeeModule
 * @notice Withdraw fee module that values PAXG asymmetrically at the vault boundary so that any PAXG:XAU
 * pricing error favors remaining shareholders rather than the withdrawer.
 * @dev The accountant quotes PAXG at its pegged price (1 PAXG = 1 XAU) in both directions. This module
 * charges a withdraw fee equal to the excess of PAXG's market value in gold over the peg, so the
 * withdrawer is effectively paid out at max(1, p) XAU per PAXG, where p is the market PAXG:XAU rate. When
 * PAXG trades at or below peg (p <= 1) the fee is zero - the pegged valuation already favors the vault.
 *
 * The fee is taken in shares (the offer asset). The consuming WithdrawQueue deducts it from the order's
 * offer amount before the withdraw and routes it to the fee recipient (the vault). NOTE: shares sent to
 * the vault are NOT burned by the ERC20; for these fees to actually accrue to NAV, the fee recipient and
 * the offchain NAV calculation must treat vault-held shares as nonexistent (excluded from both total
 * value and total supply). That accounting is a deployment/queue concern, out of scope for this module.
 *
 * The rate provider and supported withdraw asset are immutable. To change either, deploy a new module and
 * point the queue at it via its setFeeModule path; this module holds no admin surface of its own.
 */
contract PaxgDynamicWithdrawFeeModule is IFeeModule {

    using FixedPointMathLib for uint256;

    /**
     * @notice The pegged PAXG:XAU price of exactly 1, in 18-decimal fixed point (1e18). PAXG is pegged to
     * one troy ounce of gold, so this is the reference price the fee corrects toward. Matches PAXG's 18
     * decimals and the rate provider's precision.
     */
    uint256 public constant PEG_PRICE = 1e18;

    /**
     * @notice Rate provider reporting the market PAXG:XAU rate (XAU per PAXG), in 18-decimal fixed point
     * (PEG_PRICE = 1.0).
     * @dev Reverts on stale feeds. See calculateOfferFees for the queue-liveness implication of that revert.
     */
    IRateProvider public immutable RATE_PROVIDER;

    /**
     * @notice The only withdraw (want) asset this module prices. Any other want asset reverts.
     */
    IERC20 public immutable PAXG;

    error ZeroAddress();
    error InvalidWantAsset(address wantAsset);

    /**
     * @notice Initialize the module.
     * @param _rateProvider PAXG:XAU rate provider (XAU per PAXG, 18-decimal fixed point, PEG_PRICE = 1.0).
     * @param _paxg The PAXG token this module is authorized to price.
     */
    constructor(IRateProvider _rateProvider, IERC20 _paxg) {
        if (address(_rateProvider) == address(0)) revert ZeroAddress();
        if (address(_paxg) == address(0)) revert ZeroAddress();
        RATE_PROVIDER = _rateProvider;
        PAXG = _paxg;
    }

    /**
     * @notice Calculate the share-denominated withdraw fee for an order.
     * @dev feeAmount = amount * (p - 1) / p when p > 1, else 0, where p is the market PAXG:XAU rate.
     * Denominated against p (not the peg), so the fraction is always < 1. Rounds up, favoring the vault.
     * Reverts if wantAsset is not PAXG, or (via the rate provider) on stale data.
     * @param amount Share amount being offered by the order.
     * @param wantAsset Must equal PAXG.
     * @return feeAmount Fee to withhold, denominated in shares.
     */
    function calculateOfferFees(
        uint256 amount,
        IERC20, /* offerAsset */
        IERC20 wantAsset,
        address /* receiver */
    )
        external
        view
        override
        returns (uint256 feeAmount)
    {
        if (address(wantAsset) != address(PAXG)) revert InvalidWantAsset(address(wantAsset));

        // Market PAXG:XAU rate (XAU per PAXG), 18-decimal fixed point.
        //
        // RISK (accepted): getRate() reverts on a stale/unavailable feed. WithdrawQueue.processOrders calls
        // this inside a sequential loop, OUTSIDE its try/catch, so a single stale read reverts the ENTIRE
        // batch. The orders are not lost - they remain queued and process once the feed is fresh - but no
        // order in that batch can settle until then. This is the queue-blocking failure the no-slippage
        // decision (KPD 1) was wary of; it is accepted on the basis that the backend pauses withdrawal
        // processing during stale/volatile windows rather than pushing batches that will revert.
        uint256 price = RATE_PROVIDER.getRate();

        // effectivePrice = max(peg, p): never pay PAXG out above peg. When p <= peg the fee fraction is zero
        // (numerator below is 0), so the branch collapses and no fee is taken.
        uint256 effectivePrice = price > PEG_PRICE ? price : PEG_PRICE;

        // feeFraction = (p - 1) / p, denominated against the effectivePrice, not the peg.
        // mulDivUp rounds the fee up, in the vault's favor (withdrawer receives slightly less).
        //
        // RISK (accepted): there is no max-fee bound and no per-order slippage backstop on withdrawals
        // (KPD 1). Whatever price the oracle reports is applied verbatim. A wrong-but-plausible reading
        // (e.g. a transient depeg or a feed glitch that stays under the staleness threshold) silently
        // overcharges the withdrawer, and nothing on-chain catches it. Accepted per project decision;
        // the only mitigation is the offchain worst-case threshold / processing pause, not this contract.
        feeAmount = amount.mulDivUp(effectivePrice - PEG_PRICE, effectivePrice);
    }

}
