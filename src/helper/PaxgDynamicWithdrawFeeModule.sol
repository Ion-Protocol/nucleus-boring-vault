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
 * charges a withdraw fee with two components:
 *   1. A dynamic depeg fee equal to the excess of PAXG's market value in gold over the peg, so the
 *      withdrawer is effectively paid out at max(1, p) XAU per PAXG, where p is the market PAXG:XAU rate.
 *      When PAXG trades at or below peg (p <= 1) this component is zero - the pegged valuation already
 *      favors the vault.
 *   2. A fixed fee of FIXED_FEE_BPS basis points, charged on every withdrawal regardless of price.
 * The two components are summed and the total is capped at the order amount so the fee can never exceed
 * the shares offered.
 *
 * The fee is taken in shares (the offer asset). The consuming WithdrawQueue deducts it from the order's
 * offer amount before the withdraw and routes it to the fee recipient (the vault). NOTE: shares sent to
 * the vault are NOT burned by the ERC20; for these fees to actually accrue to NAV, the fee recipient and
 * the offchain NAV calculation must treat vault-held shares as nonexistent (excluded from both total
 * value and total supply). That accounting is a deployment/queue concern, out of scope for this module.
 *
 * The immutables bind the module to one vault; this module holds no admin surface. To change any of them,
 * deploy a new module and repoint the queue via setFeeModule.
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
     * @notice Basis-point denominator. 10_000 bps = 100%.
     */
    uint256 private constant BPS_DIVISOR = 10_000;

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

    /**
     * @notice The vault share token (BoringVault). The order's offer asset must equal it, binding the module
     * to the one vault whose accountant pegs PAXG to XAU 1:1. Any other offer asset reverts.
     */
    IERC20 public immutable SHARES;

    /**
     * @notice Fixed withdrawal fee, in basis points, charged on every withdrawal in addition to the dynamic
     * depeg fee. Set once at construction so the fixed fee rate cannot be changed after deployment.
     * Bounded to BPS_DIVISOR (100%) at construction.
     */
    uint256 public immutable FIXED_FEE_BPS;

    error ZeroAddress();
    error InvalidFixedFeeBps(uint256 fixedFeeBps);
    error InvalidOfferAsset(address offerAsset);
    error InvalidWantAsset(address wantAsset);

    /**
     * @notice Initialize the module.
     * @param _rateProvider PAXG:XAU rate provider (XAU per PAXG, 18-decimal fixed point, PEG_PRICE = 1.0).
     * @param _paxg The PAXG token this module is authorized to price.
     * @param _shares The vault share token (BoringVault) that withdrawals from this vault offer.
     * @param _fixedFeeBps Fixed fee in basis points, charged on every withdrawal. Must be <= BPS_DIVISOR.
     */
    constructor(IRateProvider _rateProvider, IERC20 _paxg, IERC20 _shares, uint256 _fixedFeeBps) {
        if (address(_rateProvider) == address(0)) revert ZeroAddress();
        if (address(_paxg) == address(0)) revert ZeroAddress();
        if (address(_shares) == address(0)) revert ZeroAddress();
        if (_fixedFeeBps > BPS_DIVISOR) revert InvalidFixedFeeBps(_fixedFeeBps);
        RATE_PROVIDER = _rateProvider;
        PAXG = _paxg;
        SHARES = _shares;
        FIXED_FEE_BPS = _fixedFeeBps;
    }

    /**
     * @notice Calculate the share-denominated withdraw fee for an order.
     * @dev feeAmount = min(amount, dynamicFee + fixedFee), where:
     *   - dynamicFee = amount * (p - 1) / p when p > 1, else 0 (p is the market PAXG:XAU rate, denominated
     *     against p so the fraction is always < 1); and
     *   - fixedFee = amount * FIXED_FEE_BPS / BPS_DIVISOR, a flat fee charged on every withdrawal.
     * The total is capped at the order amount. Reverts if the offer asset is not SHARES, the want asset is
     * not PAXG, or the rate provider reports stale data.
     * @param amount Share amount being offered by the order.
     * @param offerAsset Must equal SHARES.
     * @param wantAsset Must equal PAXG.
     * @return feeAmount Fee to withhold, denominated in shares.
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
        if (address(offerAsset) != address(SHARES)) revert InvalidOfferAsset(address(offerAsset));
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

        // Dynamic depeg fee: takes the fraction (p - 1) / p of the amount, evaluated against effectivePrice
        // (not the peg), so nothing is taken at/below peg. mulDivUp rounds up, in the vault's favor
        // (withdrawer receives slightly less).
        //
        // RISK (accepted): there is no max-fee bound and no per-order slippage backstop on withdrawals
        // (KPD 1). Whatever price the oracle reports is applied verbatim. A wrong-but-plausible reading
        // (e.g. a transient depeg or a feed glitch that stays under the staleness threshold) silently
        // overcharges the withdrawer, and nothing on-chain catches it. Accepted per project decision;
        // the only mitigation is the offchain worst-case threshold / processing pause, not this contract.
        uint256 dynamicFee = amount.mulDivUp(effectivePrice - PEG_PRICE, effectivePrice);

        // Fixed fee: takes the fraction FIXED_FEE_BPS / BPS_DIVISOR of the amount, charged unconditionally
        // (even at/below peg). mulDivUp rounds up, in the vault's favor, consistent with the dynamic fee.
        uint256 fixedFee = amount.mulDivUp(FIXED_FEE_BPS, BPS_DIVISOR);

        feeAmount = dynamicFee + fixedFee;

        // Never withhold more shares than the order offers. For any realistic price (p ~ 1) the two
        // components sum well below the amount; the cap only binds at an extreme premium (the dynamic
        // fraction approaching 1) or on dust orders where round-up dominates. Capping preserves the
        // fee <= amount invariant the WithdrawQueue relies on.
        if (feeAmount > amount) feeAmount = amount;
    }

}
