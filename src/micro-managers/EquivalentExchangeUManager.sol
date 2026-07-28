// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { UManager, ERC20 } from "src/micro-managers/UManager.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title EquivalentExchangeUManager
 * @notice UManager that executes a batch of merkle-verified BoringVault actions
 *         and enforces that the aggregate USD value of a stored basket of tokens
 *         does not decrease.
 * @dev Basket tokens are valued in USD. Most tokens are expected to be USD-denominated and are treated
 *      as worth $1 per whole token after decimal normalization. A token may instead be flagged as
 *      oracle-priced, in which case its per-whole-token USD price is read from an `IRateProvider` at
 *      execution time and applied to its balance. The same oracle conversion is used when paying the
 *      subsidy in a non-USD token.
 *
 *      Which basket tokens are oracle-priced is recorded as a bitmap (`oracleFlags`): bit `i` is set iff
 *      the basket token at index `i` (in `basketTokens` order) is oracle-priced. A fully USD basket
 *      therefore requires no oracle lookups.
 *
 *      Subsidy, if required, is pulled from an approval-based subsidy payer. The subsidy payer must
 *      pre-approve the UManager to spend the subsidy token; if the approved/available amount is
 *      insufficient, the call reverts.
 *
 *      Oracle security assumptions:
 *      - Each oracle is an `IRateProvider` returning the token's price in USD scaled to
 *        `NORMALIZED_DECIMALS` (1e18 == $1.00). The owner is responsible for configuring oracles that
 *        perform their own staleness and sanity checks and that cannot be manipulated within a block.
 *      - A reverting or zero-returning oracle causes `execute` to revert, which is preferable to
 *        valuing a basket token incorrectly.
 */
contract EquivalentExchangeUManager is UManager {

    using SafeTransferLib for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCast for uint256;

    /// @notice Decimal scale used for normalizing token amounts and expressing USD value.
    uint256 internal constant NORMALIZED_DECIMALS = 18;

    /// @notice One whole unit of normalized (USD) value, i.e. 10**NORMALIZED_DECIMALS. Equal to $1.00 of
    /// normalized value and to one whole token of a normalized balance.
    uint256 internal constant NORMALIZED_ONE = 10 ** NORMALIZED_DECIMALS;

    /// @notice Maximum number of basket tokens. Bounded by the width of `oracleFlags` (256 bits), so every
    /// basket index maps to a distinct flag bit.
    uint256 internal constant MAX_BASKET_TOKENS = 256;

    /// @notice Selector for increaseAllowance(address,uint256).
    bytes4 internal constant INCREASE_ALLOWANCE_SELECTOR = 0x39509351;

    /// @notice Basket tokens whose aggregate USD value this UManager preserves across an `execute` batch.
    EnumerableSet.AddressSet internal basketTokens;

    /// @notice Bitmap of which basket tokens are oracle-priced: bit `i` is set iff the token at index `i`
    /// in `basketTokens` is priced through an oracle rather than treated as a 1:1 USD asset.
    /// @dev Indices align with `basketTokens.values()`; `setBasketTokens` rebuilds both together.
    bytes32 internal oracleFlags;

    /// @notice Maps a basket token to the rate provider used to convert its balance to USD.
    /// @dev `oracleFlags`, not this mapping, is the source of truth for whether a token is oracle-priced.
    /// Entries are read only when a token's flag bit is set, so USD tokens never hit the mapping, and it is
    /// allowed to be "dirty": stale entries left behind when the basket changes are never read.
    mapping(address => IRateProvider) internal tokenOracles;

    error EmptyBasket();
    error BasketTooLarge();
    error DuplicateToken(address token);
    error TokenNotInBasket();
    error InvalidRate(address token);
    error InsufficientSubsidy();
    error DanglingApproval();
    error TokenDeltaLengthMismatch();
    error TokenDeltaViolation(
        address token, uint256 balanceBefore, uint256 balanceAfter, int256 balanceDelta, int256 allowedBalanceDelta
    );

    event BasketTokensUpdated(BasketToken[] tokens);
    event Executed(
        address indexed caller,
        ERC20 indexed subsidyToken,
        uint256 totalBeforeNormalized,
        uint256 totalAfterNormalized,
        uint256 subsidyAmount,
        uint256 subsidyAmountNormalized
    );

    /**
     * @notice A basket token together with its USD price source.
     * @param token The basket token.
     * @param oracle Rate provider returning `token`'s price in USD scaled to `NORMALIZED_DECIMALS`
     * (1e18 == $1.00). The zero address marks `token` as a 1:1 USD asset, priced by decimal
     * normalization alone with no oracle lookup.
     */
    struct BasketToken {
        ERC20 token;
        IRateProvider oracle;
    }

    /**
     * @notice A batch of merkle-verified BoringVault actions, as parallel arrays.
     * @dev The downstream manager enforces that all five arrays are the same length, so this contract skips those
     * checks.
     * @param manageProofs Merkle proof for each action.
     * @param decodersAndSanitizers Decoder/sanitizer to extract each action's gated addresses.
     * @param targets Contract each action calls.
     * @param targetData Calldata for each action.
     * @param values ETH value for each action.
     */
    struct ManageCalls {
        bytes32[][] manageProofs;
        address[] decodersAndSanitizers;
        address[] targets;
        bytes[] targetData;
        uint256[] values;
    }

    constructor(address _owner, address _manager, address _boringVault) UManager(_owner, _manager, _boringVault) { }

    /**
     * @notice Sets the basket of tokens used for accounting, along with each token's USD price source.
     * @dev The basket is exactly the set of tokens whose balance changes `execute` checks, and defines the
     * order `allowableTokenDelta` (and the `oracleFlags` bitmap) bind to. A token with a zero `oracle` is
     * treated as a 1:1 USD asset; a token with a non-zero `oracle` is priced through it. Duplicate token
     * addresses are rejected so the stored basket is an exact, order-preserving image of the input.
     * @param tokens Basket tokens and their price sources. At most `MAX_BASKET_TOKENS` entries.
     * @custom:access OWNER_ROLE / MULTISIG_ROLE should be granted authority.
     */
    function setBasketTokens(BasketToken[] calldata tokens) external requiresAuth {
        // Remove all existing tokens by popping from the end. Length shrinks on each removal, so we must
        // iterate backwards to avoid out-of-bounds reads. Stale `tokenOracles` entries are intentionally
        // left in place; they are never read once their flag bit is cleared below.
        uint256 existingLength = basketTokens.length();
        for (uint256 i = existingLength; i > 0; --i) {
            basketTokens.remove(basketTokens.at(i - 1));
        }

        uint256 newLength = tokens.length;
        // Each basket index must map to a distinct bit of `oracleFlags`.
        if (newLength > MAX_BASKET_TOKENS) revert BasketTooLarge();

        // Add new tokens, building the oracle bitmap in lockstep so bit `i` describes the token at index
        // `i`. Duplicates revert so the stored basket is an exact, order-preserving image of the input.
        bytes32 flags;
        for (uint256 i; i < newLength; ++i) {
            address token = address(tokens[i].token);
            // add() returns false when the token is already present in the set.
            if (!basketTokens.add(token)) revert DuplicateToken(token);

            IRateProvider oracle = tokens[i].oracle;
            if (address(oracle) != address(0)) {
                tokenOracles[token] = oracle;
                flags = _setOracleFlag(flags, i);
            }
        }
        oracleFlags = flags;

        // Duplicates revert above, so the stored set matches the input exactly. Emit the calldata
        // directly rather than reading the set back out of storage.
        emit BasketTokensUpdated(tokens);
    }

    /**
     * @notice Returns the basket tokens, each with its USD price source, in stored order.
     */
    function getBasketTokens() external view returns (BasketToken[] memory tokens) {
        address[] memory values = basketTokens.values();
        bytes32 flags = oracleFlags;
        uint256 length = values.length;
        tokens = new BasketToken[](length);
        for (uint256 i; i < length; ++i) {
            tokens[i] = BasketToken({
                token: ERC20(values[i]),
                oracle: _hasOracleFlag(flags, i) ? tokenOracles[values[i]] : IRateProvider(address(0))
            });
        }
    }

    /**
     * @notice Returns whether a token is part of the basket.
     */
    function isBasketToken(ERC20 token) external view returns (bool) {
        return basketTokens.contains(address(token));
    }

    /**
     * @notice Executes a batch of merkle-verified BoringVault actions, enforces a per-token bound on
     *         each basket token's balance change over the batch, and enforces that the vault's aggregate
     *         basket value (in USD) does not decrease (topping up any shortfall from the subsidy payer).
     * @dev `allowableTokenDelta` must be exactly as long as the basket, so every basket token is bounded. Movement is
     *      measured over the batch ONLY; the subsidy pulled afterwards is not counted against any bound.
     *
     *      Each token's USD value is its decimal-normalized balance for USD assets, or that balance priced
     *      through the token's oracle for oracle-priced assets. A token's oracle rate is read once and
     *      applied to both the before and after balances, so the two totals cannot disagree on price.
     *
     *      Subsidy, if needed, is pulled from the indicated subsidy payer using ERC20 transferFrom; the
     *      payer must have approved the UManager. The amount pulled is the aggregate USD shortfall,
     *      converted to the subsidy token (through its oracle when non-USD) and rounded up.
     * @param calls Batch of merkle-verified BoringVault actions to execute.
     * @param subsidyPayer Address that provides the subsidy tokens via approval.
     * @param subsidyToken Token to use as subsidy. Must be a basket token.
     * @param allowableTokenDelta Minimum signed balance change tolerated for each basket token, in native units,
     * parallel to `getBasketTokens()`. `execute` reverts if a token's actual change (balanceAfter - balanceBefore)
     * is less than its entry. For example, -100 lets the balance fall by up to 100, +100 requires it to rise by at
     * least 100, and 0 requires it not to fall.
     * @return subsidyAmount Subsidy pulled from `subsidyPayer`, in `subsidyToken`'s native units. This is the
     * amount actually transferred, inclusive of the conversion round-up.
     * @custom:access STRATEGIST_ROLE should be granted authority - confined to calls the merkle root already
     * allows, and cannot lower the basket's total value. Note `allowableTokenDelta` is supplied by the caller, so it
     * guards against a bad route, not against a bad strategist.
     */
    function execute(
        ManageCalls calldata calls,
        address subsidyPayer,
        ERC20 subsidyToken,
        int256[] calldata allowableTokenDelta
    )
        external
        requiresAuth
        returns (uint256 subsidyAmount)
    {
        // Read the basket once into memory. The set should not change mid-execution, but snapshotting it
        // guarantees every loop below indexes the same tokens, so `allowableTokenDelta[i]`, `tokens[i]` and
        // the `oracleFlags` bit `i` can never drift out of alignment.
        address[] memory tokens = basketTokens.values();
        uint256 basketLength = tokens.length;

        if (basketLength == 0) revert EmptyBasket();
        if (!basketTokens.contains(address(subsidyToken))) revert TokenNotInBasket();
        if (allowableTokenDelta.length != basketLength) revert TokenDeltaLengthMismatch();

        // Snapshot the pre-batch balances the delta bounds are measured against. Normalizing/pricing is
        // deferred to the post-batch loop, which reads each token's decimals and oracle anyway.
        uint256[] memory beforeBalances = new uint256[](basketLength);

        for (uint256 i; i < basketLength; ++i) {
            beforeBalances[i] = ERC20(tokens[i]).balanceOf(boringVault);
        }

        // Execute the merkle-verified action batch directly from BoringVault.
        _manageVaultWithMerkleVerification(calls);

        // Bounds constrain what the batch did, so they are checked before any subsidy is pulled. The
        // per-token loop is factored out to keep `execute` under the stack limit. It also reports the rate
        // the subsidy token was valued at, so the subsidy is priced identically to the shortfall.
        (uint256 totalBefore, uint256 totalAfter, uint256 subsidyRate) =
            _checkAndValueBasket(tokens, beforeBalances, allowableTokenDelta, address(subsidyToken));

        // Cover any aggregate shortfall using the indicated subsidy token. The subsidy inflow is
        // intentionally not counted against subsidyToken's delta bound.
        uint256 subsidyAmountNormalized;
        if (totalAfter < totalBefore) {
            uint256 shortfall = totalBefore - totalAfter;
            (subsidyAmount, subsidyAmountNormalized) =
                _coverShortfall(shortfall, subsidyPayer, subsidyToken, subsidyRate);
            totalAfter += subsidyAmountNormalized;
        }

        // Final invariant check. _coverShortfall either covers the shortfall or
        // reverts; this assert is a self-documenting guard against future
        // changes to subsidy behavior.
        assert(totalAfter >= totalBefore);

        // Ensure no approvals to basket tokens remain outstanding.
        _enforceNoDanglingApprovals(calls);

        emit Executed(msg.sender, subsidyToken, totalBefore, totalAfter, subsidyAmount, subsidyAmountNormalized);
    }

    /**
     * @notice Checks each basket token's balance delta and totals the vault's basket value, in USD, both
     *         before and after the batch.
     * @dev Factored out of `execute` purely to stay under the stack limit. Each oracle-priced token (per
     * the `oracleFlags` bitmap) has its rate read once and applied to both balances, so the two totals
     * cannot disagree on price.
     * @param tokens Basket token addresses snapshotted at the start of `execute`.
     * @param beforeBalances Pre-batch vault balances, parallel to `tokens`.
     * @param allowableTokenDelta Minimum signed balance change tolerated for each token, parallel to `tokens`.
     * @param subsidyToken The token a subsidy would be paid in, whose rate is captured for `_coverShortfall`.
     * @return totalBefore Aggregate USD value of the basket before the batch.
     * @return totalAfter Aggregate USD value of the basket after the batch.
     * @return subsidyRate The bitmap-gated rate used to value `subsidyToken` (0 if it is a USD asset).
     */
    function _checkAndValueBasket(
        address[] memory tokens,
        uint256[] memory beforeBalances,
        int256[] calldata allowableTokenDelta,
        address subsidyToken
    )
        internal
        view
        returns (uint256 totalBefore, uint256 totalAfter, uint256 subsidyRate)
    {
        bytes32 flags = oracleFlags;
        uint256 basketLength = tokens.length;
        for (uint256 i; i < basketLength; ++i) {
            address token = tokens[i];
            uint256 balanceBefore = beforeBalances[i];
            uint256 balanceAfter = ERC20(token).balanceOf(boringVault);

            _checkTokenDelta(token, balanceBefore, balanceAfter, allowableTokenDelta[i]);

            // A token's decimals are unlikely to change mid-execution, but a single decimals() read
            // normalizes both balances, so the two totals cannot disagree on scale. rate == 0 marks a 1:1
            // USD asset; an oracle-priced asset (its flag bit set) is priced with one getRate() reading
            // applied to both balances.
            uint8 decimals = ERC20(token).decimals();
            uint256 rate = _hasOracleFlag(flags, i) ? _readRate(token, tokenOracles[token]) : 0;

            // Capture the subsidy token's rate as it is valued, so `_coverShortfall` can reuse it.
            if (token == subsidyToken) subsidyRate = rate;

            totalBefore += _valueInUsd(balanceBefore, decimals, rate);
            totalAfter += _valueInUsd(balanceAfter, decimals, rate);
        }
    }

    /**
     * @notice Covers a normalized (USD) shortfall by transferring subsidy from the
     *         subsidy payer to the vault.
     * @dev The subsidy token must be a basket token. The payer must have a
     *      sufficient balance and approval to cover the shortfall.
     * @param shortfall Shortfall in normalized (USD) units.
     * @param subsidyPayer Address that provides the subsidy tokens via approval.
     * @param subsidyToken Token to use as subsidy.
     * @param rate USD price of one whole `subsidyToken` scaled to NORMALIZED_DECIMALS, or 0 for a USD
     * asset. Supplied by `_checkAndValueBasket` so the subsidy is priced exactly as the shortfall was.
     * @return subsidyAmount Amount of subsidy transferred, in the subsidy token's native units.
     * @return subsidyAmountNormalized Total normalized (USD) value of subsidy transferred.
     */
    function _coverShortfall(
        uint256 shortfall,
        address subsidyPayer,
        ERC20 subsidyToken,
        uint256 rate
    )
        internal
        returns (uint256 subsidyAmount, uint256 subsidyAmountNormalized)
    {
        uint8 decimals = subsidyToken.decimals();

        uint256 balance = subsidyToken.balanceOf(subsidyPayer);
        uint256 allowance = subsidyToken.allowance(subsidyPayer, address(this));
        uint256 available = balance < allowance ? balance : allowance;

        // Guard in USD terms. Because the guard uses the same flooring conversion as pricing and
        // `_usdValueToTokenAmount` rounds up, `available`'s USD value >= shortfall implies the converted
        // subsidyAmount <= available. So the transfer below can never pull more than is available.
        if (_valueInUsd(available, decimals, rate) < shortfall) revert InsufficientSubsidy();

        subsidyAmount = _usdValueToTokenAmount(shortfall, decimals, rate);

        subsidyToken.safeTransferFrom(subsidyPayer, boringVault, subsidyAmount);

        // Re-value the actual amount transferred for accounting. The round-up in `_usdValueToTokenAmount`
        // guarantees this is >= shortfall, so the value invariant holds.
        subsidyAmountNormalized = _valueInUsd(subsidyAmount, decimals, rate);
    }

    /**
     * @notice Reverts if a basket token's balance change over the batch is below the caller's minimum.
     * @dev toInt256() reverts rather than wrapping to a negative if a balance ever exceeds 2**255 - 1, e.g. a
     *      token that flash-mints an enormous supply into the vault mid-batch.
     * @param token Basket token being checked.
     * @param balanceBefore Vault balance before the batch.
     * @param balanceAfter Vault balance after the batch.
     * @param allowedBalanceDelta Minimum signed change the caller will accept for this token.
     */
    function _checkTokenDelta(
        address token,
        uint256 balanceBefore,
        uint256 balanceAfter,
        int256 allowedBalanceDelta
    )
        internal
        pure
    {
        int256 delta = balanceAfter.toInt256() - balanceBefore.toInt256();
        if (delta < allowedBalanceDelta) {
            revert TokenDeltaViolation(token, balanceBefore, balanceAfter, delta, allowedBalanceDelta);
        }
    }

    //============================== APPROVAL TRACKING ===============================

    /**
     * @notice Ensures that any ERC20#approve or ERC20#increaseAllowance calls made
     *         by the vault to basket tokens during the batch have been fully reset
     *         to zero by the end of execution.
     * @param calls Batch of merkle-verified BoringVault actions.
     */
    function _enforceNoDanglingApprovals(ManageCalls calldata calls) internal view {
        uint256 callsLength = calls.targets.length;

        for (uint256 i; i < callsLength; ++i) {
            address target = calls.targets[i];
            if (!basketTokens.contains(target)) continue;

            bytes calldata targetData = calls.targetData[i];

            // Length check is >= 68 because some token contracts (e.g., compiled
            // with older Solidity versions) may tolerate trailing calldata on
            // low-level calls rather than reverting. approve(address,uint256) and
            // increaseAllowance(address,uint256) both require 4 + 32 + 32 = 68
            // bytes at minimum.
            if (targetData.length < 68) continue;

            bytes4 selector = bytes4(targetData[0:4]);
            if (selector != ERC20.approve.selector && selector != INCREASE_ALLOWANCE_SELECTOR) continue;

            // Spender is the first argument, located at byte offset 4 (selector)
            // + 32 (zero-padded address) = 36. Amount is the second argument,
            // spanning the next 32 bytes. This layout is identical for approve
            // and increaseAllowance.
            (address spender, uint256 amount) = abi.decode(targetData[4:68], (address, uint256));
            // A zero-amount approval cannot create a dangling allowance, so it
            // does not need to be checked. Note: this only skips the current call;
            // any preceding or subsequent non-zero approval to the same token and
            // spender will still be checked normally.
            if (amount == 0) continue;

            if (ERC20(target).allowance(boringVault, spender) != 0) {
                revert DanglingApproval();
            }
        }
    }

    /**
     * @notice Forwards a batch to ManagerWithMerkleVerification.
     * @dev Kept separate only to keep `execute` under the stack limit; inlining it is "stack too deep".
     * @param calls Batch of merkle-verified BoringVault actions.
     */
    function _manageVaultWithMerkleVerification(ManageCalls calldata calls) internal {
        manager.manageVaultWithMerkleVerification(
            calls.manageProofs, calls.decodersAndSanitizers, calls.targets, calls.targetData, calls.values
        );
    }

    /**
     * @notice Reads a token's USD price from its oracle, reverting on a zero rate.
     * @param token Basket token being priced (used only for the revert reason).
     * @param oracle Rate provider for `token`.
     * @return rate USD price of one whole `token`, scaled to `NORMALIZED_DECIMALS`.
     */
    function _readRate(address token, IRateProvider oracle) internal view returns (uint256 rate) {
        rate = oracle.getRate();
        if (rate == 0) revert InvalidRate(token);
    }

    /**
     * @notice Values a token balance in normalized (USD) units.
     * @dev `rate == 0` is the sentinel for a 1:1 USD asset, whose decimal-normalized balance already is
     * its USD value. Otherwise the normalized balance is priced by `rate` (USD per whole token, scaled to
     * NORMALIZED_DECIMALS), multiplying before dividing and flooring the result.
     * @param balance Token balance in native units.
     * @param decimals Token decimals.
     * @param rate USD price of one whole token scaled to NORMALIZED_DECIMALS, or 0 for a USD asset.
     * @return USD value scaled to NORMALIZED_DECIMALS.
     */
    function _valueInUsd(uint256 balance, uint8 decimals, uint256 rate) internal pure returns (uint256) {
        uint256 normalized = _normalize(balance, decimals);
        if (rate == 0) return normalized;
        return (normalized * rate) / NORMALIZED_ONE;
    }

    /**
     * @notice Converts a normalized (USD) value to a token's native units, rounding up so the result is
     *         never worth less than the input value.
     * @dev `rate == 0` denormalizes directly (USD asset). Otherwise the USD value is first converted to a
     * normalized token amount, rounding up, then denormalized (which also rounds up).
     * @param usdValue Value in normalized (USD) units.
     * @param decimals Token decimals.
     * @param rate USD price of one whole token scaled to NORMALIZED_DECIMALS, or 0 for a USD asset.
     * @return Token amount in native units.
     */
    function _usdValueToTokenAmount(uint256 usdValue, uint8 decimals, uint256 rate) internal pure returns (uint256) {
        if (rate == 0) return _denormalize(usdValue, decimals);
        // ceil(usdValue * NORMALIZED_ONE / rate): normalized token amount whose USD value is >= usdValue.
        uint256 normalizedToken = ((usdValue * NORMALIZED_ONE) + rate - 1) / rate;
        return _denormalize(normalizedToken, decimals);
    }

    /**
     * @notice Returns whether the basket token at `index` is oracle-priced, per an `oracleFlags` snapshot.
     */
    function _hasOracleFlag(bytes32 flags, uint256 index) internal pure returns (bool) {
        return ((uint256(flags) >> index) & 1) == 1;
    }

    /**
     * @notice Sets the oracle-priced bit for `index` in an `oracleFlags` value.
     * @dev `index` is always < MAX_BASKET_TOKENS (256), so the shift stays in range.
     */
    function _setOracleFlag(bytes32 flags, uint256 index) internal pure returns (bytes32) {
        return bytes32(uint256(flags) | (uint256(1) << index));
    }

    /**
     * @notice Rescales an amount to NORMALIZED_DECIMALS (18).
     */
    function _normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals <= NORMALIZED_DECIMALS) {
            return amount * (10 ** (NORMALIZED_DECIMALS - decimals));
        }
        return amount / (10 ** (decimals - NORMALIZED_DECIMALS));
    }

    /**
     * @notice Rescales an amount from NORMALIZED_DECIMALS (18) to a token's
     *         native decimals, rounding up to avoid underestimating.
     */
    function _denormalize(uint256 normalizedAmount, uint8 decimals) internal pure returns (uint256) {
        if (decimals <= NORMALIZED_DECIMALS) {
            uint256 factor = 10 ** (NORMALIZED_DECIMALS - decimals);
            return (normalizedAmount + factor - 1) / factor;
        }
        return normalizedAmount * (10 ** (decimals - NORMALIZED_DECIMALS));
    }

}
