// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { IGPv2Settlement } from "src/interfaces/IGPv2Settlement.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { CowSwapOrderLib } from "src/libraries/CowSwapOrderLib.sol";

/**
 * @title CowSwapHelper
 * @notice A helper contract that becomes the CoW Protocol order owner on the vault's behalf. The
 *         BoringVault calls `placeOrder` via `ManagerWithMerkleVerification`; the helper pulls the sell
 *         token in, becomes the order owner, and pre-signs the order directly. Proceeds are routed straight
 *         back to the vault via the order's `receiver`.
 * @dev Custody model: because `setPreSignature` requires `owner == msg.sender`, and the helper is the
 *      caller, the helper must be the order `owner`. The relayer therefore pulls the sell token from the
 *      *helper*, so the vault must move the sell token into the helper before settlement. The helper holds
 *      that balance for the order's whole lifetime.
 *
 *      Consequences of the helper holding funds:
 *      - The helper is a second custodian with its own access control; it is no longer true that all vault
 *        assets live in the BoringVault.
 *      - `receiver` is set to the vault, so *filled* proceeds go straight to the vault with no withdrawal
 *        step. But an expired / unfilled / partially-filled order leaves residual sell tokens stranded in
 *        the helper, which must be swept back with `returnToVault`.
 *
 *      Pricing safety: CoW settles asynchronously, so there is no post-trade balance invariant to lean on.
 *      The order's `buyAmount` is the only on-chain protection against a bad fill, validated here against a
 *      floor derived from an `IRateProvider` oracle: `buyAmount >= fairRate * sellAmount * (1 - maxSlippageBps)`.
 *
 *      Oracle security assumptions (the rate provider, its decimals, and the slippage are all caller-supplied,
 *      so this is load-bearing):
 *      - `rateProvider`, `rateDecimals`, and `maxSlippageBps` are constrained OUTSIDE this contract, by the
 *        decoder/sanitizer and merkle root that gate the vault's `placeOrder` call: the merkle tree only
 *        authorizes calls matching a vetted leaf. The decoder for `placeOrder` MUST pin the `rateProvider`,
 *        `sellToken`, and `buyToken` addresses AND the `rateDecimals` and `maxSlippageBps` values. Otherwise a
 *        strategist could pass a near-zero-rate provider, an oversized `rateDecimals` (inflating the divisor so
 *        the fair amount collapses to zero), or a 100% `maxSlippageBps` - each drives the floor to zero - and
 *        drain the sell token. NOTE the asymmetry: an address-sanitizing decoder pins the addresses by default,
 *        but `rateDecimals` and `maxSlippageBps` are numeric fields the decoder must be written to include
 *        explicitly. This contract only defends in depth (rejecting a zero rate, requiring
 *        `maxSlippageBps <= 100%`); it does NOT itself cap how loose the floor may be.
 *      - `getRate()` must return the fair price of one whole `sellToken` denominated in whole `buyToken`,
 *        scaled to `rateDecimals` fixed-point decimals, as a single positive `uint256`; `rateDecimals` must
 *        match the provider's actual scale. It must perform its own staleness and sanity checks and be
 *        unmanipulable within a block (wrap raw Chainlink feeds in an adapter such as `EthPerTokenRateProvider`).
 *        A reverting or zero-returning provider reverts the order, which is preferable to mispricing it.
 */
contract CowSwapHelper {

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Basis-point denominator for the slippage bound.
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @notice The BoringVault this helper serves: the source of sell tokens and the `receiver` of proceeds.
    address internal immutable boringVault;

    /// @notice CoW settlement contract this helper authorizes orders on.
    IGPv2Settlement internal immutable settlement;

    /// @notice Relayer that pulls sell tokens at settlement; the spender the helper must approve.
    address internal immutable vaultRelayer;

    /// @notice Cached EIP-712 domain separator of `settlement`, read once at deploy.
    bytes32 internal immutable domainSeparator;

    /**
     * @notice Raw order fields supplied by the strategist (via the vault). Some safety-critical fields
     *         (`receiver`, `kind`, balance kinds) are forced to safe constants on
     *         rebuild and so are absent here.
     * @param sellToken Token to sell.
     * @param buyToken Token to buy; proceeds are always sent to the BoringVault.
     * @param sellAmount Amount of `sellToken` to offer.
     * @param buyAmount Minimum buy amount; must satisfy the oracle-derived floor for the given provider.
     * @param validTo Order expiry (unix timestamp); must be in the future. Not otherwise bounded - a stale
     * order can be cancelled at will via `cancelOrder`.
     * @param partiallyFillable Whether the order may be filled in multiple parts. CoW enforces the same
     * `buyAmount / sellAmount` limit price on every partial fill (rounding the executed buy amount up, in the
     * vault's favor), so the oracle floor validated here protects each fill regardless of this flag; residual
     * sell tokens from an incomplete order are swept back with `returnToVault`.
     * @param rateProvider Oracle returning the `buyToken`-per-`sellToken` rate, scaled to `rateDecimals`
     * decimals.
     * @param rateDecimals Fixed-point decimals the oracle's rate is expressed in; used as the divisor when
     * mapping the sell amount through the rate. Caller-supplied and, like `rateProvider`.
     * @param maxSlippageBps Tolerated slippage below the oracle's fair rate, in basis points.
     */
    struct OrderParams {
        ERC20 sellToken;
        ERC20 buyToken;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bool partiallyFillable;
        IRateProvider rateProvider;
        uint8 rateDecimals;
        uint256 maxSlippageBps;
    }

    error PriceTooLow(uint256 buyAmountNormalized, uint256 minBuyAmountNormalized);
    error ZeroAmount();
    error OrderExpired();
    error DanglingApproval(address token);
    error InvalidRate(address rateProvider);
    error InvalidSlippage();
    error ZeroAddress();
    error NotBoringVault();

    event OrderPlaced(
        address indexed sellToken, address indexed buyToken, uint256 sellAmount, uint256 buyAmount, bytes orderUid
    );
    event OrderCancelled(bytes orderUid);
    event FundsReturned(address indexed token, uint256 amount);

    /// @notice Restricts a function to the BoringVault, i.e. calls routed through
    /// `ManagerWithMerkleVerification`.
    modifier onlyBoringVault() {
        if (msg.sender != boringVault) revert NotBoringVault();
        _;
    }

    /**
     * @notice Deploys the helper and caches the settlement immutables.
     * @param _boringVault The BoringVault whose funds this helper trades and returns to, and the only
     * permitted caller of the order functions.
     * @param _settlement The CoW settlement contract.
     */
    constructor(address _boringVault, address _settlement) {
        // receiver is hardcoded to boringVault when building orders; a zero vault would silently route
        // proceeds to the order owner (this helper) under CoW's RECEIVER_SAME_AS_OWNER marker.
        if (_boringVault == address(0)) revert ZeroAddress();
        if (_settlement == address(0)) revert ZeroAddress();

        boringVault = _boringVault;
        settlement = IGPv2Settlement(_settlement);
        vaultRelayer = IGPv2Settlement(_settlement).vaultRelayer();
        domainSeparator = IGPv2Settlement(_settlement).domainSeparator();
    }

    /**
     * @notice Pulls the sell token from the vault, approves the relayer, and pre-signs the order with the
     *         helper as owner and the vault as receiver.
     * @dev Intended to be called by the BoringVault through `ManagerWithMerkleVerification`. The vault must
     *      have granted this helper an allowance of exactly `sellAmount` for `sellToken`; any residual
     *      allowance after the pull reverts. The relayer approval overwrites
     *      any prior allowance, so this assumes one live order per sell token at a time. Callable only by the
     *      BoringVault; which orders are permitted is gated upstream by the merkle root.
     * @param params Raw order fields; see `OrderParams`.
     * @return orderUid The pre-signed order UID.
     */
    function placeOrder(OrderParams calldata params) external onlyBoringVault returns (bytes memory orderUid) {
        orderUid = _buildAndValidateOrderUid(params);

        // Move the sell token from the vault into this helper.
        params.sellToken.safeTransferFrom(boringVault, address(this), params.sellAmount);
        if (params.sellToken.allowance(boringVault, address(this)) != 0) {
            revert DanglingApproval(address(params.sellToken));
        }

        // Approve the relayer to pull the sell token at settlement.
        params.sellToken.safeApprove(vaultRelayer, params.sellAmount);

        // Authorize the order on-chain.
        settlement.setPreSignature(orderUid, true);

        emit OrderPlaced(
            address(params.sellToken), address(params.buyToken), params.sellAmount, params.buyAmount, orderUid
        );
    }

    /**
     * @notice Cancels a previously pre-signed order by clearing the helper's signature for its UID.
     * @dev Triggered by the BoringVault (routed through `ManagerWithMerkleVerification`). `setPreSignature`
     *      still succeeds because the order's owner is this helper, which is the account calling it.
     * @param orderUid The UID to revoke.
     */
    function cancelOrder(bytes calldata orderUid) external onlyBoringVault {
        settlement.setPreSignature(orderUid, false);
        emit OrderCancelled(orderUid);
    }

    /**
     * @notice Sweeps the helper's entire balance of `token` back to the BoringVault.
     * @dev The custody cost of this design: residual sell tokens from an expired, unfilled, or partially
     *      filled order sit in the helper until this is called. Callable only by the BoringVault.
     * @param token Token to return to the vault.
     */
    function returnToVault(ERC20 token) external onlyBoringVault {
        uint256 balance = token.balanceOf(address(this));
        if (balance != 0) {
            token.safeTransfer(boringVault, balance);
            emit FundsReturned(address(token), balance);
        }
    }

    /**
     * @notice Validates `params` against the oracle-derived price floor, then builds the canonical order
     *         (forcing all safety-critical fields) and returns its UID.
     * @dev Every field folded into the digest is either validated or forced to a safe constant, so nothing
     *      reaches the signed order unchecked.
     * @param params Raw order fields.
     * @return orderUid The reconstructed UID.
     */
    function _buildAndValidateOrderUid(OrderParams calldata params) internal view returns (bytes memory orderUid) {
        if (params.sellAmount == 0 || params.buyAmount == 0) revert ZeroAmount();
        if (params.validTo <= block.timestamp) revert OrderExpired();
        if (params.maxSlippageBps > BPS_DENOMINATOR) revert InvalidSlippage();

        uint256 rate = params.rateProvider.getRate();
        if (rate == 0) revert InvalidRate(address(params.rateProvider));

        uint256 sellNormalized = CowSwapOrderLib.normalize(params.sellAmount, params.sellToken.decimals());
        uint256 buyNormalized = CowSwapOrderLib.normalize(params.buyAmount, params.buyToken.decimals());

        // `rate` is buyToken-per-sellToken in `rateDecimals` fixed-point, so dividing the 18-decimal sell amount
        // by 10 ** rateDecimals yields the fair buy amount back in 18-decimal terms, comparable to buyNormalized.
        uint256 fairBuyNormalized = sellNormalized.mulDivUp(rate, 10 ** params.rateDecimals);
        uint256 minBuyNormalized = fairBuyNormalized.mulDivUp(BPS_DENOMINATOR - params.maxSlippageBps, BPS_DENOMINATOR);
        if (buyNormalized < minBuyNormalized) revert PriceTooLow(buyNormalized, minBuyNormalized);

        CowSwapOrderLib.Data memory order = CowSwapOrderLib.Data({
            sellToken: address(params.sellToken),
            buyToken: address(params.buyToken),
            receiver: boringVault,
            sellAmount: params.sellAmount,
            buyAmount: params.buyAmount,
            validTo: params.validTo,
            // Empty appData: cannot encode settlement hooks, so no arbitrary calls ride along.
            appData: bytes32(0),
            feeAmount: 0,
            kind: CowSwapOrderLib.KIND_SELL,
            partiallyFillable: params.partiallyFillable,
            sellTokenBalance: CowSwapOrderLib.BALANCE_ERC20,
            buyTokenBalance: CowSwapOrderLib.BALANCE_ERC20
        });

        bytes32 digest = CowSwapOrderLib.hash(order, domainSeparator);
        // Owner is always this helper: `setPreSignature` requires `owner == msg.sender`, and the helper is the
        // caller, so it must own the order.
        orderUid = CowSwapOrderLib.packOrderUid(digest, address(this), params.validTo);
    }

}
