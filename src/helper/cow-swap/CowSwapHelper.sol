// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { IGPv2Settlement } from "src/interfaces/IGPv2Settlement.sol";
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
 *      governance-set, periodically-refreshed `minPrice` floor that the strategist can meet but not undercut.
 */
contract CowSwapHelper is Auth {

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Fixed-point scale (1e18) that `minPrice` values and normalized amounts are expressed in.
    uint256 internal constant PRICE_ONE = 1e18;

    /// @notice The BoringVault this helper serves: the source of sell tokens and the `receiver` of proceeds.
    address internal immutable boringVault;

    /// @notice CoW settlement contract this helper authorizes orders on.
    IGPv2Settlement internal immutable settlement;

    /// @notice Relayer that pulls sell tokens at settlement; the spender the helper must approve.
    address internal immutable vaultRelayer;

    /// @notice Cached EIP-712 domain separator of `settlement`, read once at deploy.
    bytes32 internal immutable domainSeparator;

    /**
     * @notice A governance-set minimum execution price for a `(sellToken, buyToken)` pair.
     * @param price Minimum whole buy-tokens per whole sell-token, 18-decimal fixed point. Non-zero.
     * @param updatedAt Timestamp of the last refresh; drives the staleness guard and the enabled check.
     */
    struct MinPrice {
        uint192 price;
        uint64 updatedAt;
    }

    /**
     * @notice Raw order fields supplied by the strategist (via the vault). Safety-critical fields
     *         (`receiver`, `kind`, `partiallyFillable`, balance kinds) are forced to safe constants on
     *         rebuild and so are absent here.
     * @param sellToken Token to sell (must be an enabled pair with `buyToken`).
     * @param buyToken Token to buy; proceeds are always sent to the BoringVault.
     * @param sellAmount Amount of `sellToken` to offer.
     * @param buyAmount Minimum buy amount; must satisfy the stored `minPrice` floor.
     * @param validTo Order expiry (unix seconds); must be in the future and within `maxOrderValidity`.
     * @param appData Off-chain metadata hash; must equal `allowedAppData`.
     */
    struct OrderParams {
        ERC20 sellToken;
        ERC20 buyToken;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
    }

    /// @notice Minimum execution price per pair, keyed by `keccak256(abi.encode(sellToken, buyToken))`.
    mapping(bytes32 => MinPrice) internal minPrices;

    /// @notice Maximum age a `minPrice` may reach before `placeOrder` rejects it as stale.
    uint256 internal maxPriceAge;

    /// @notice Maximum lifetime an order's `validTo` may extend past `block.timestamp`.
    uint256 internal maxOrderValidity;

    /// @notice The only `appData` value orders may carry; pins settlement hooks to a vetted value.
    bytes32 internal allowedAppData;

    error PairNotEnabled(address sellToken, address buyToken);
    error StalePrice(address sellToken, address buyToken);
    error PriceTooLow(uint256 buyAmountNormalized, uint256 minBuyAmountNormalized);
    error ZeroAmount();
    error InvalidAppData();
    error OrderExpired();
    error ValidityTooLong();
    error InvalidPrice();
    error DanglingApproval(address token);

    event MinPriceUpdated(address indexed sellToken, address indexed buyToken, uint256 price, uint256 updatedAt);
    event MaxPriceAgeUpdated(uint256 maxPriceAge);
    event MaxOrderValidityUpdated(uint256 maxOrderValidity);
    event AllowedAppDataUpdated(bytes32 allowedAppData);
    event OrderPlaced(
        address indexed sellToken, address indexed buyToken, uint256 sellAmount, uint256 buyAmount, bytes orderUid
    );
    event OrderCancelled(bytes orderUid);
    event FundsReturned(address indexed token, uint256 amount);

    /**
     * @notice Deploys the helper and caches the settlement immutables.
     * @param _owner Owner for `Auth`.
     * @param _authority Authority for `Auth`.
     * @param _boringVault The BoringVault whose funds this helper trades and returns to.
     * @param _settlement The CoW settlement contract.
     * @param _maxPriceAge Initial staleness bound for min prices.
     * @param _maxOrderValidity Initial cap on order lifetime.
     */
    constructor(
        address _owner,
        Authority _authority,
        address _boringVault,
        address _settlement,
        uint256 _maxPriceAge,
        uint256 _maxOrderValidity
    )
        Auth(_owner, _authority)
    {
        boringVault = _boringVault;
        settlement = IGPv2Settlement(_settlement);
        vaultRelayer = IGPv2Settlement(_settlement).vaultRelayer();
        domainSeparator = IGPv2Settlement(_settlement).domainSeparator();
        maxPriceAge = _maxPriceAge;
        maxOrderValidity = _maxOrderValidity;
    }

    //============================== ADMIN ===============================

    /**
     * @notice Sets (and timestamps) the minimum execution price for a pair, enabling it for trading.
     * @dev This is the periodic on-chain price refresh the async model depends on. Callable by
     *      OWNER_ROLE / MULTISIG_ROLE.
     * @param sellToken Sell side of the pair.
     * @param buyToken Buy side of the pair.
     * @param price Minimum whole buy-tokens per whole sell-token, 18-decimal fixed point. Non-zero.
     */
    function setMinPrice(address sellToken, address buyToken, uint192 price) external requiresAuth {
        if (price == 0) revert InvalidPrice();
        minPrices[_pairKey(sellToken, buyToken)] = MinPrice({ price: price, updatedAt: uint64(block.timestamp) });
        emit MinPriceUpdated(sellToken, buyToken, price, block.timestamp);
    }

    /// @notice Sets the staleness bound applied to min prices. Callable by OWNER_ROLE / MULTISIG_ROLE.
    function setMaxPriceAge(uint256 _maxPriceAge) external requiresAuth {
        maxPriceAge = _maxPriceAge;
        emit MaxPriceAgeUpdated(_maxPriceAge);
    }

    /// @notice Sets the cap on order lifetime. Callable by OWNER_ROLE / MULTISIG_ROLE.
    function setMaxOrderValidity(uint256 _maxOrderValidity) external requiresAuth {
        maxOrderValidity = _maxOrderValidity;
        emit MaxOrderValidityUpdated(_maxOrderValidity);
    }

    /// @notice Sets the only permitted `appData`. Callable by OWNER_ROLE / MULTISIG_ROLE.
    function setAllowedAppData(bytes32 _allowedAppData) external requiresAuth {
        allowedAppData = _allowedAppData;
        emit AllowedAppDataUpdated(_allowedAppData);
    }

    //============================== STRATEGIST ===============================

    /**
     * @notice Pulls the sell token from the vault, approves the relayer, and pre-signs the order with the
     *         helper as owner and the vault as receiver.
     * @dev Intended to be called by the BoringVault through `ManagerWithMerkleVerification`. The vault must
     *      have granted this helper an allowance of exactly `sellAmount` for `sellToken`; any residual
     *      allowance after the pull reverts, mirroring `EquivalentExchange`. The relayer approval overwrites
     *      any prior allowance, so this assumes one live order per sell token at a time. Callable by
     *      STRATEGIST-authorized callers (the vault).
     * @param params Raw order fields; see `OrderParams`.
     * @return orderUid The pre-signed order UID.
     */
    function placeOrder(OrderParams calldata params) external requiresAuth returns (bytes memory orderUid) {
        // Helper is the order owner (so it can be the setPreSignature caller); vault stays the receiver.
        orderUid = _buildAndValidateOrderUid(params, address(this));

        // Move the sell token from the vault into the helper, since the relayer will pull from the owner.
        params.sellToken.safeTransferFrom(boringVault, address(this), params.sellAmount);
        if (params.sellToken.allowance(boringVault, address(this)) != 0) {
            revert DanglingApproval(address(params.sellToken));
        }

        // Approve the relayer to pull the sell token at settlement.
        params.sellToken.safeApprove(vaultRelayer, params.sellAmount);

        // Authorize the order on-chain; owner packed into the UID is this helper == msg.sender.
        settlement.setPreSignature(orderUid, true);

        emit OrderPlaced(
            address(params.sellToken), address(params.buyToken), params.sellAmount, params.buyAmount, orderUid
        );
    }

    /**
     * @notice Cancels a previously pre-signed order by clearing the helper's signature for its UID.
     * @dev Called directly (no merkle routing) because the helper is the order owner. Callable by
     *      STRATEGIST-authorized callers.
     * @param orderUid The UID to revoke.
     */
    function cancelOrder(bytes calldata orderUid) external requiresAuth {
        settlement.setPreSignature(orderUid, false);
        emit OrderCancelled(orderUid);
    }

    /**
     * @notice Sweeps the helper's entire balance of `token` back to the BoringVault.
     * @dev The custody cost of this design: residual sell tokens from an expired, unfilled, or partially
     *      filled order sit in the helper until this is called. Callable by STRATEGIST-authorized callers.
     * @param token Token to return to the vault.
     */
    function returnToVault(ERC20 token) external requiresAuth {
        uint256 balance = token.balanceOf(address(this));
        if (balance != 0) {
            token.safeTransfer(boringVault, balance);
            emit FundsReturned(address(token), balance);
        }
    }

    //============================== VIEW ===============================

    /// @notice Returns the stored min price and last-update time for a pair.
    function getMinPrice(address sellToken, address buyToken) external view returns (uint192 price, uint64 updatedAt) {
        MinPrice memory mp = minPrices[_pairKey(sellToken, buyToken)];
        return (mp.price, mp.updatedAt);
    }

    //============================== INTERNAL ===============================

    /**
     * @notice Validates `params` against the stored price floor and freshness/lifetime bounds, then builds
     *         the canonical order (forcing all safety-critical fields) and returns its UID.
     * @dev Every field folded into the digest is either validated (`sellToken`/`buyToken`/`sellAmount`/
     *      `buyAmount`/`validTo`/`appData`) or forced to a safe constant (`receiver`, `feeAmount`, `kind`,
     *      `partiallyFillable`, balance kinds), so nothing reaches the signed order unchecked. `owner` is the
     *      helper (it must be the `setPreSignature` caller); `receiver` is always the vault.
     * @param params Raw order fields.
     * @param owner The account to embed as the order owner (and thus the `setPreSignature` caller).
     * @return orderUid The reconstructed UID.
     */
    function _buildAndValidateOrderUid(
        OrderParams calldata params,
        address owner
    )
        internal
        view
        returns (bytes memory orderUid)
    {
        if (params.sellAmount == 0 || params.buyAmount == 0) revert ZeroAmount();
        if (params.appData != allowedAppData) revert InvalidAppData();
        if (params.validTo <= block.timestamp) revert OrderExpired();
        if (params.validTo > block.timestamp + maxOrderValidity) revert ValidityTooLong();

        MinPrice memory mp = minPrices[_pairKey(address(params.sellToken), address(params.buyToken))];
        if (mp.updatedAt == 0) revert PairNotEnabled(address(params.sellToken), address(params.buyToken));
        if (block.timestamp - mp.updatedAt > maxPriceAge) {
            revert StalePrice(address(params.sellToken), address(params.buyToken));
        }

        // Enforce buyAmount >= sellAmount * minPrice, comparing both sides at 18 decimals. The minimum is
        // rounded up so any rounding favors the vault.
        uint256 sellNormalized = CowSwapOrderLib.normalize(params.sellAmount, params.sellToken.decimals());
        uint256 buyNormalized = CowSwapOrderLib.normalize(params.buyAmount, params.buyToken.decimals());
        uint256 minBuyNormalized = sellNormalized.mulDivUp(mp.price, PRICE_ONE);
        if (buyNormalized < minBuyNormalized) revert PriceTooLow(buyNormalized, minBuyNormalized);

        CowSwapOrderLib.Data memory order = CowSwapOrderLib.Data({
            sellToken: address(params.sellToken),
            buyToken: address(params.buyToken),
            receiver: boringVault,
            sellAmount: params.sellAmount,
            buyAmount: params.buyAmount,
            validTo: params.validTo,
            appData: params.appData,
            feeAmount: 0,
            kind: CowSwapOrderLib.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: CowSwapOrderLib.BALANCE_ERC20,
            buyTokenBalance: CowSwapOrderLib.BALANCE_ERC20
        });

        bytes32 digest = CowSwapOrderLib.hash(order, domainSeparator);
        orderUid = CowSwapOrderLib.packOrderUid(digest, owner, params.validTo);
    }

    /// @notice Derives the storage key for a `(sellToken, buyToken)` price entry.
    function _pairKey(address sellToken, address buyToken) internal pure returns (bytes32) {
        return keccak256(abi.encode(sellToken, buyToken));
    }

}
