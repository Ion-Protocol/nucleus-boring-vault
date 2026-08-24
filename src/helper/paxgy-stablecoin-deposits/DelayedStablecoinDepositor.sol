// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";

import { Attestation } from "@predicate/interfaces/IPredicateRegistry.sol";

import { DistributorCodeDepositor } from "src/helper/DistributorCodeDepositor.sol";
import { Pausable } from "src/helper/Pausable.sol";

/**
 * @title DelayedStablecoinDepositor
 * @notice Order helper attached to a dedicated offer-receiver {BoringVault}. Accepts user stablecoin deposits against a
 *         backend-signed {Quote} pending an off-chain conversion to PAXG, then mints PAXGy (BoringVault shares) to the
 *         quote's receiver on the depositor's behalf.
 * @dev This contract owns the order bookkeeping for the PAXGy stablecoin deposit flow but does NOT custody the
 *      deposited stablecoins: on submission they are transferred immediately into the {offerReceiver}, a dedicated
 *      {BoringVault} that holds funds in flight to Paxos. Because PAXGy can only be minted from PAXG, a permissioned
 *      strategist converts the staged stablecoins to PAXG off-chain (via Paxos) and delivers the PAXG here to complete
 *      the deposit. Orders are independent: each is acted on by its id, so a single failing order never blocks the
 *      others.
 *
 *      Signed-quote model (mirrors {TransitStation}):
 *        - Order terms are priced off-chain and EIP-712 signed by the trusted {quoteSigner}. A {Quote} is a bearer
 *          instrument: whoever submits it funds the offer, and the eventual PAXGy (or a refund) goes to the quote's
 *          `receiver`.
 *        - An order's uuid is the EIP-712 digest of its quote, used directly as the order id, so it is fully
 *          determined by the signed terms and identical no matter who submits it. The `salt` field gives
 *          otherwise-identical quotes distinct uuids.
 *        - {usedUuids} is a permanent ledger: a uuid is marked used on submission and never cleared, so a given quote
 *          can be submitted at most once — even after its order record is deleted on fulfillment/refund.
 *        - The on-chain config ({isStablecoinSupported}, {minOrderSize}/{maxOrderSize}) is retained as a
 *          defense-in-depth backstop: even a compromised signer can only ever land orders within these bounds.
 *
 *      Fund custody and movement:
 *        - The staged stablecoins live in {offerReceiver}. This contract never holds them (aside from PAXG transiently
 *          during {settleOrder}).
 *        - The transfer of staged stablecoins to the fixed Paxos deposit address is performed OUTSIDE this contract,
 *          while the order is live, by the strategist via the {offerReceiver} vault's {ManagerWithMerkleVerification}
 *          (which enforces the permitted destination via its merkle root).
 *        - The PAXG-to-PAXGy mint is routed through the canonical {DistributorCodeDepositor}, NOT the teller directly,
 *          so these deposits inherit the same supply cap, KYT/attestation, fee, and distributor-code policy as any
 *          other PAXG deposit and cannot bypass the global supply cap.
 *
 *      Order flow:
 *        - submit -> stages the stablecoins in {offerReceiver} and records the order.
 *        - settle -> fills part or all of the order (depositing PAXG into PAXGy via {DistributorCodeDepositor}),
 *                    refunds the unfilled remainder, and deletes the record.
 *
 *      Roles are enforced by the configured {Authority}. The intended wiring is:
 *        - submitter        -> {submitOrder}/{submitOrderWithPermit}.
 *        - STRATEGIST role  -> {settleOrder}.
 *        - PAUSER role      -> {pause}; ADMIN role/owner -> {unpause}.
 *        - ADMIN role/owner -> all config setters.
 *      The owner is always authorized (see solmate {Auth}).
 *
 *      Pausing halts new submissions ({submitOrder}, {submitOrderWithPermit}) and the fill leg of {settleOrder} as an
 *      emergency stop for a compromised signer/strategist. A refund-only settlement ({settleOrder} with no fill) stays
 *      callable while paused so staged funds can always be unwound.
 *
 *      Beneficiary model: the beneficiary of an order (who receives the PAXGy on fulfillment, or the stablecoin on
 *      refund) is the `receiver` from the signed quote, recorded on the order.
 * @custom:security-contact security@paxoslabs.com
 */
contract DelayedStablecoinDepositor is Auth, Pausable {

    using SafeTransferLib for ERC20;
    using SafeCast for uint256;

    // ========================================= TYPES =========================================

    /**
     * @notice Backend-priced deposit terms, EIP-712 signed by {quoteSigner}. Bearer instrument: anyone may submit a
     *         valid quote (they pay the offer amount; the eventual PAXGy goes to the quote's `receiver`). Amounts are
     * in
     *         the offer asset's own decimals.
     * @param offerAsset The stablecoin to deposit.
     * @param offerAmount The stablecoin amount to stage for conversion.
     * @param wantAmount PAXGy wanted for a full fill. Together with `offerAmount` this sets the quote's
     *        stablecoin:PAXGy rate, which prices partial fills, and it is the PAXGy a full fill must mint.
     * @param receiver Beneficiary of the order: recipient of the minted PAXGy (or of a refund).
     * @param deadline Unix timestamp after which the quote may no longer be submitted.
     * @param salt Entropy so otherwise-identical quotes get distinct uuids.
     */
    struct Quote {
        ERC20 offerAsset;
        uint256 offerAmount;
        uint256 wantAmount;
        address receiver;
        uint256 deadline;
        bytes32 salt;
    }

    /**
     * @notice A single live delayed stablecoin deposit order. Exists from submission until fulfilled or refunded, when
     *         it is deleted.
     * @param offerAmount Stablecoin amount staged for this order, in the stablecoin's own decimals. The unfilled
     *        portion is returned on settlement.
     * @param wantAmount PAXGy wanted for a full fill. With `offerAmount` it sets the stablecoin:PAXGy rate that
     *        prices partial fills in {settleOrder}.
     * @param offerAsset The stablecoin deposited for this order. A zero value marks a non-existent (never-created or
     *        already-resolved) order.
     * @param receiver The beneficiary from the signed quote: recipient of the PAXGy on fulfillment or the refunded
     *        stablecoin on refund.
     */
    struct Order {
        uint128 offerAmount;
        uint128 wantAmount;
        ERC20 offerAsset;
        address receiver;
    }

    // ========================================= CONSTANTS =========================================

    // EIP-712 type hashes. The domain separator is hand-rolled (OZ's EIP712 base pulls in StorageSlot which needs
    // solc >=0.8.24, and this repo pins 0.8.21). Recomputed live in {_domainSeparator}, so it is fork-safe.
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant QUOTE_TYPEHASH = keccak256(
        "Quote(address offerAsset,uint256 offerAmount,uint256 wantAmount,address receiver,uint256 deadline,bytes32 salt)"
    );

    // ========================================= IMMUTABLES =========================================

    /// @notice The dedicated offer-receiver vault that custodies deposited stablecoins in flight to Paxos. Funds move
    /// out of it to Paxos via its own {ManagerWithMerkleVerification}; on refund it approves this contract to pull.
    address public immutable offerReceiver;

    /// @notice The canonical PAXGy depositor used to mint shares from PAXG. Applies the shared supply cap, KYT,
    ///         fee, and distributor-code policy, and mints shares directly to the beneficiary.
    DistributorCodeDepositor public immutable paxgyDepositor;

    /// @notice The PAXG token deposited into {paxgyDepositor} to mint PAXGy. Must be a supported deposit asset there.
    ERC20 public immutable paxg;

    // ========================================= STATE =========================================

    /// @notice Trusted backend key; every submitted {Quote} must carry its EIP-712 signature.
    address public quoteSigner;

    /// @notice Permanent replay ledger: whether a uuid (quote digest) has ever been submitted. Never cleared.
    mapping(uint256 => bool) public usedUuids;

    /// @notice Whether a stablecoin is accepted for new orders.
    mapping(ERC20 => bool) public isStablecoinSupported;

    /// @notice Maximum net stablecoin amount permitted in a single order, per stablecoin (0 disables new orders).
    mapping(ERC20 => uint256) public maxOrderSize;

    /// @notice Minimum net stablecoin amount permitted in a single order, per stablecoin.
    mapping(ERC20 => uint256) public minOrderSize;

    /// @notice Live order data, keyed by order id: the uint256 of the quote's EIP-712 digest, which is also its uuid.
    ///         Deleted on settlement.
    mapping(uint256 => Order) public orders;

    // ========================================= EVENTS =========================================

    event OrderSubmitted(uint256 indexed orderId, address indexed depositor, address indexed receiver, Quote quote);

    /// @dev Emitted when an order is settled and deleted. `fillAmount` is the PAXGy the fill was priced at,
    ///      `sharesMinted` what the depositor actually minted (>= `fillAmount`), and `refundAmount` the stablecoin
    ///      returned for the unfilled portion; a pure fill or pure refund just zeroes the unused side.
    event OrderSettled(
        uint256 indexed orderId,
        address indexed beneficiary,
        uint256 paxgDeposited,
        uint256 fillAmount,
        uint256 sharesMinted,
        uint256 refundAmount
    );

    event QuoteSignerSet(address indexed signer);
    event StablecoinConfigUpdated(ERC20 indexed stablecoin, bool supported, uint256 minOrderSize, uint256 maxOrderSize);
    event ERC20Rescued(ERC20 indexed token, address indexed to, uint256 amount);

    // ========================================= ERRORS =========================================

    error ZeroAddress();
    error StablecoinNotSupported(ERC20 stablecoin);
    error AmountOutsideBounds(uint256 amount, uint256 min, uint256 max);
    error QuoteExpired(uint256 deadline);
    error InvalidSigner(address recoveredSigner);
    error UuidAlreadyUsed(uint256 orderId);
    error OrderNotFound(uint256 orderId);
    error PermitFailedAndAllowanceTooLow();
    error ZeroWantAmount();
    error FillExceedsOrder(uint256 fillAmount, uint256 wantAmount);
    error RefundMismatch(uint256 expectedRefund, uint256 refundAmount);

    // ========================================= CONSTRUCTOR =========================================

    /**
     * @param _offerReceiver The dedicated offer-receiver vault (a {BoringVault}) that custodies staged stablecoins for
     *        this flow. Typed as `address` since only plain transfers are made to/from it.
     * @param _paxgyDepositor The canonical PAXGy {DistributorCodeDepositor}; must support {_paxg} for deposits.
     * @param _paxg The PAXG token used to mint PAXGy.
     * @param _quoteSigner The trusted backend key that signs {Quote}s.
     * @param _owner Initial owner (always authorized).
     */
    constructor(
        address _offerReceiver,
        DistributorCodeDepositor _paxgyDepositor,
        ERC20 _paxg,
        address _quoteSigner,
        address _owner
    )
        Auth(_owner, Authority(address(0)))
    {
        if (_owner == address(0)) revert ZeroAddress();
        if (_offerReceiver == address(0)) revert ZeroAddress();
        if (address(_paxgyDepositor) == address(0)) revert ZeroAddress();
        if (address(_paxg) == address(0)) revert ZeroAddress();
        if (_quoteSigner == address(0)) revert ZeroAddress();

        offerReceiver = _offerReceiver;
        paxgyDepositor = _paxgyDepositor;
        paxg = _paxg;
        quoteSigner = _quoteSigner;

        emit QuoteSignerSet(_quoteSigner);
    }

    // ========================================= ADMIN: CONFIG =========================================

    /**
     * @notice Rotate the trusted quote signer.
     * @dev Highest-stakes setter: the signer authorizes every order's terms. On-chain backstops still bound what a
     *      new (or compromised) signer can do.
     * @param signer New signer.
     */
    function setQuoteSigner(address signer) external requiresAuth {
        if (signer == address(0)) revert ZeroAddress();
        quoteSigner = signer;
        emit QuoteSignerSet(signer);
    }

    /**
     * @notice Add, update, or disable a supported stablecoin and its per-order bounds.
     * @dev Set `supported` to false (or `maxSize` to 0) to stop accepting new orders for the asset. Existing orders
     *      are unaffected and can still be fulfilled or refunded. These bounds are an on-chain backstop on top of the
     *      signed quote.
     * @param stablecoin The stablecoin to configure.
     * @param supported Whether new orders may be submitted for it.
     * @param minSize Minimum net order size (in stablecoin decimals).
     * @param maxSize Maximum net order size / per-order cap (in stablecoin decimals).
     */
    function setStablecoinConfig(
        ERC20 stablecoin,
        bool supported,
        uint256 minSize,
        uint256 maxSize
    )
        external
        requiresAuth
    {
        if (address(stablecoin) == address(0)) revert ZeroAddress();

        isStablecoinSupported[stablecoin] = supported;
        minOrderSize[stablecoin] = minSize;
        maxOrderSize[stablecoin] = maxSize;

        emit StablecoinConfigUpdated(stablecoin, supported, minSize, maxSize);
    }

    /**
     * @notice Rescue tokens sent to or stuck in this contract. Admin-gated.
     * @dev Does not reconcile against outstanding orders; the admin is trusted not to remove funds owed to live
     *      orders. Staged stablecoins are held in {offerReceiver}, not here, so this cannot touch them.
     */
    function rescueERC20(ERC20 token, address to, uint256 amount) external requiresAuth {
        if (address(token) == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        token.safeTransfer(to, amount);
        emit ERC20Rescued(token, to, amount);
    }

    // ========================================= EMERGENCY =========================================

    /**
     * @notice Emergency stop: halts new submissions ({submitOrder}, {submitOrderWithPermit}) and the fill leg of
     *         {settleOrder} so a compromised signer or strategist can be frozen before more orders land or mint.
     * @dev A refund-only settlement ({settleOrder} with `fillAmount == 0`) stays callable while paused so staged funds
     *      can always be unwound.
     */
    function pause() external requiresAuth {
        _pause();
    }

    /// @notice Resume submissions and fills after a pause.
    function unpause() external requiresAuth {
        _unpause();
    }

    // ========================================= EXTERNAL: USER =========================================

    /**
     * @notice Submit a backend-signed quote: moves the stablecoin into {offerReceiver} and records a live order whose
     *         beneficiary is the quote's `receiver`. The order id is the quote's EIP-712 digest (uuid).
     * @dev Gated by {requiresAuth} so access can be scoped at deploy, but the signed quote is the substantive
     *      gate. No fee is taken here; the PAXGy deposit fee is applied once, on the PAXG leg, by the
     *      {DistributorCodeDepositor} during {settleOrder}.
     * @param quote Backend-priced deposit terms. See {Quote}.
     * @param signature EIP-712 signature over `quote` by {quoteSigner}.
     * @return orderId The id of the created order (also the quote uuid).
     */
    function submitOrder(
        Quote calldata quote,
        bytes calldata signature
    )
        external
        requiresAuth
        whenNotPaused
        returns (uint256 orderId)
    {
        orderId = _submitOrder(quote, signature);
    }

    /**
     * @notice Same as {submitOrder} but consumes an EIP-2612 permit first, so approve + submit happen in one tx.
     * @dev A failed permit (already approved / front-run) falls back to an allowance check rather than reverting.
     * @param quote Backend-priced deposit terms. See {Quote}.
     * @param signature EIP-712 signature over `quote` by {quoteSigner}.
     * @param permitDeadline Permit expiry.
     * @param v Permit signature component.
     * @param r Permit signature component.
     * @param s Permit signature component.
     * @return orderId The id of the created order (also the quote uuid).
     */
    function submitOrderWithPermit(
        Quote calldata quote,
        bytes calldata signature,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        requiresAuth
        whenNotPaused
        returns (uint256 orderId)
    {
        // solhint-disable-next-line no-empty-blocks
        try quote.offerAsset.permit(msg.sender, address(this), quote.offerAmount, permitDeadline, v, r, s) { }
        catch {
            if (quote.offerAsset.allowance(msg.sender, address(this)) < quote.offerAmount) {
                revert PermitFailedAndAllowanceTooLow();
            }
        }
        orderId = _submitOrder(quote, signature);
    }

    // ========================================= EXTERNAL: STRATEGIST =========================================

    /**
     * @notice Settle an order: fill part or all of it by depositing PAXG into PAXGy for the beneficiary, refund the
     *         offer asset for whatever is unfilled, and delete the order.
     * @dev Strategist-gated. The fill is priced at the quote's stablecoin:PAXGy rate (`offerAmount`:`wantAmount`), and
     *      the refund must be exactly the unfilled remainder:
     *
     *          offerAmountFilled = ceil(fillAmount * offerAmount / wantAmount)
     *          require: refundAmount == offerAmount - offerAmountFilled
     *
     *      The filled amount rounds up, so the refund rounds down by at most one unit and any dust stays in the vault.
     * The fill leg deposits
     *      `paxgAmount` PAXG (which the strategist must have delivered here) through {DistributorCodeDepositor} with
     *      `minimumMint == fillAmount`; the refund leg pulls `refundAmount` from {offerReceiver}, which must have
     *      approved this contract in the same manager batch. While paused, only refunds are allowed (`fillAmount == 0`)
     *      so open orders can still be unwound.
     * @param orderId The order to settle.
     * @param paxgAmount PAXG to deposit for the fill leg; 0 for a pure refund.
     * @param fillAmount PAXGy the fill is priced at, and the deposit's `minimumMint`; must not exceed `wantAmount`.
     * @param refundAmount Stablecoin to refund; must equal the exact unfilled remainder.
     * @param distributorCode Distributor code for the fill, forwarded to {DistributorCodeDepositor}.
     * @param attestation Predicate KYT attestation for the fill; may be empty when KYT is disabled for PAXG.
     * @return sharesMinted PAXGy minted to the beneficiary (0 for a pure refund).
     */
    function settleOrder(
        uint256 orderId,
        uint256 paxgAmount,
        uint256 fillAmount,
        uint256 refundAmount,
        bytes calldata distributorCode,
        Attestation calldata attestation
    )
        external
        requiresAuth
        returns (uint256 sharesMinted)
    {
        Order memory order = orders[orderId];
        if (address(order.offerAsset) == address(0)) revert OrderNotFound(orderId);

        // Filling mints new PAXGy, so it is blocked while paused; refunds stay available to unwind staged funds.
        if (fillAmount != 0 && paused()) revert EnforcedPause();

        // Value the fill at the quote's stablecoin:PAXGy rate and require the refund to be the exact unfilled
        // remainder. `wantAmount` is nonzero for any live order (enforced at submission), so the division is safe, and
        // bounding `fillAmount` by it keeps the subtraction from underflowing.
        //
        // Round the filled amount UP so any sub-unit dust stays in the vault rather than inflating the refund to the
        // beneficiary. At a full fill (fillAmount == wantAmount) it divides exactly, leaving a zero refund.
        if (fillAmount > order.wantAmount) revert FillExceedsOrder(fillAmount, order.wantAmount);
        uint256 offerAmountFilled = FixedPointMathLib.mulDivUp(fillAmount, order.offerAmount, order.wantAmount);
        uint256 expectedRefund = order.offerAmount - offerAmountFilled;
        if (refundAmount != expectedRefund) revert RefundMismatch(expectedRefund, refundAmount);

        address beneficiary = order.receiver;

        // Effects before interactions: resolve the order (delete record) before any external call.
        delete orders[orderId];

        // Fill leg: deposit PAXG via the canonical depositor, which pulls it from here and mints shares straight to the
        // beneficiary. `minimumMint == fillAmount` enforces the priced fill; clear any residual approval afterward.
        if (fillAmount != 0) {
            paxg.safeApprove(address(paxgyDepositor), paxgAmount);
            sharesMinted =
                paxgyDepositor.deposit(paxg, paxgAmount, fillAmount, beneficiary, distributorCode, attestation);
            paxg.safeApprove(address(paxgyDepositor), 0);
        }

        // Refund leg: pull the unfilled stablecoin out of the vault (which must have approved this contract) to the
        // beneficiary.
        if (refundAmount != 0) {
            order.offerAsset.safeTransferFrom(offerReceiver, beneficiary, refundAmount);
        }

        emit OrderSettled(orderId, beneficiary, paxgAmount, fillAmount, sharesMinted, refundAmount);
    }

    // ========================================= VIEW =========================================

    /// @notice Return the live order struct for `orderId` (zeroed if it does not exist).
    function getOrder(uint256 orderId) external view returns (Order memory) {
        return orders[orderId];
    }

    /**
     * @notice The order id (uuid) a given quote would produce: its EIP-712 digest as a uint256. Lets off-chain
     *         callers predict the id before submission.
     */
    function quoteOrderId(Quote calldata quote) external view returns (uint256) {
        return uint256(_hashTypedData(quote));
    }

    /// @notice EIP-712 hashStruct of `quote`.
    function hashQuote(Quote calldata quote) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                QUOTE_TYPEHASH,
                address(quote.offerAsset),
                quote.offerAmount,
                quote.wantAmount,
                quote.receiver,
                quote.deadline,
                quote.salt
            )
        );
    }

    // ========================================= INTERNAL =========================================

    /**
     * @dev Shared submit core. Verifies the signed quote and its on-chain backstops, derives the uuid from the quote
     *      digest, marks it used and records the live order (the replay-critical effects) before any external call,
     *      then stages the stablecoin in {offerReceiver}.
     */
    function _submitOrder(Quote calldata quote, bytes calldata signature) internal returns (uint256 orderId) {
        if (block.timestamp > quote.deadline) revert QuoteExpired(quote.deadline);

        // On-chain backstops (defense-in-depth against a compromised quoteSigner).
        if (!isStablecoinSupported[quote.offerAsset]) revert StablecoinNotSupported(quote.offerAsset);
        if (quote.receiver == address(0)) revert ZeroAddress();
        if (quote.wantAmount == 0) revert ZeroWantAmount(); // wantAmount sets the price, so it must be nonzero
        uint256 maxSize = maxOrderSize[quote.offerAsset];
        uint256 minSize = minOrderSize[quote.offerAsset];
        if (quote.offerAmount < minSize || quote.offerAmount > maxSize) {
            revert AmountOutsideBounds(quote.offerAmount, minSize, maxSize);
        }

        // Verify the quote is signed by the trusted backend; the digest doubles as the uuid / order id.
        bytes32 digest = _hashTypedData(quote);
        address signer = ECDSA.recover(digest, signature);
        if (signer != quoteSigner) revert InvalidSigner(signer);

        orderId = uint256(digest);
        // Replay guard: mark the uuid used forever. Checked before the order record so a resubmit reverts even after
        // the prior order was settled (and its record deleted).
        if (usedUuids[orderId]) revert UuidAlreadyUsed(orderId);
        usedUuids[orderId] = true;

        // Record the live order (with its beneficiary) before any external call.
        orders[orderId] = Order({
            offerAmount: quote.offerAmount.toUint128(),
            wantAmount: quote.wantAmount.toUint128(),
            offerAsset: quote.offerAsset,
            receiver: quote.receiver
        });

        // Move the full deposit into the offer-receiver vault immediately.
        quote.offerAsset.safeTransferFrom(msg.sender, offerReceiver, quote.offerAmount);

        emit OrderSubmitted(orderId, msg.sender, quote.receiver, quote);
    }

    /// @dev Full EIP-712 digest (`0x1901 || domainSeparator || hashStruct`) of `quote`.
    function _hashTypedData(Quote calldata quote) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(hex"1901", _domainSeparator(), hashQuote(quote)));
    }

    /// @dev EIP-712 domain separator, computed live (reads `block.chainid`) so it is fork-safe.
    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("DelayedStablecoinDepositor")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

}
