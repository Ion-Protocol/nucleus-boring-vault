// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title CowSwapOrderLib
 * @notice Pure mechanics for reconstructing a CoW Protocol order digest and UID on-chain from raw fields.
 * @dev This is the security-critical primitive shared by both CowSwap modules: because
 *      `IGPv2Settlement.setPreSignature` only sees the opaque `orderUid` (a hash), every economically
 *      meaningful field must be folded into that hash here, exactly as CoW's off-chain orderbook computes
 *      it, or the resulting UID will not match a real order (harmless) — or worse, a field left out of the
 *      hash would be one the strategist could vary freely. Keeping the hashing in one audited place means
 *      Option A and Option B cannot drift apart on this detail.
 *
 *      The field layout, type hash, and UID packing mirror CoW's `GPv2Order` library. `kind`,
 *      `sellTokenBalance`, and `buyTokenBalance` are stored as `bytes32` (the keccak of their string label)
 *      but are declared as `string` in the EIP-712 type string — that asymmetry is intentional and matches
 *      the protocol.
 */
library CowSwapOrderLib {

    /**
     * @notice A CoW Protocol order, matching `GPv2Order.Data` field-for-field.
     * @param sellToken Token sold by the order owner.
     * @param buyToken Token bought and delivered to `receiver`.
     * @param receiver Recipient of the bought tokens.
     * @param sellAmount Amount of `sellToken` offered.
     * @param buyAmount Minimum amount of `buyToken` accepted — the price floor lives here.
     * @param validTo Unix-seconds expiry after which the order can no longer settle.
     * @param appData Hash of off-chain metadata; can encode settlement hooks, so it must be pinned.
     * @param feeAmount Fee taken from the sell side.
     * @param kind `KIND_SELL` or `KIND_BUY`.
     * @param partiallyFillable Whether the order may be filled in parts.
     * @param sellTokenBalance Source-balance kind for the sell side (`BALANCE_ERC20`/`EXTERNAL`/`INTERNAL`).
     * @param buyTokenBalance Destination-balance kind for the buy side (`BALANCE_ERC20`/`INTERNAL`).
     */
    struct Data {
        address sellToken;
        address buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        bytes32 kind;
        bool partiallyFillable;
        bytes32 sellTokenBalance;
        bytes32 buyTokenBalance;
    }

    /// @notice EIP-712 type hash of the order struct. `kind`/`*Balance` are typed as `string` here even
    /// though `Data` carries them as `bytes32`; this matches CoW Protocol exactly.
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(
        "Order(address sellToken,address buyToken,address receiver,uint256 sellAmount,uint256 buyAmount,"
        "uint32 validTo,bytes32 appData,uint256 feeAmount,string kind,bool partiallyFillable,"
        "string sellTokenBalance,string buyTokenBalance)"
    );

    /// @notice `kind` value marking a sell order (exact sell amount, variable buy amount).
    bytes32 internal constant KIND_SELL = keccak256("sell");

    /// @notice `kind` value marking a buy order.
    bytes32 internal constant KIND_BUY = keccak256("buy");

    /// @notice Balance kind for plain ERC20 allowances (as opposed to Balancer internal/external balances).
    bytes32 internal constant BALANCE_ERC20 = keccak256("erc20");

    /**
     * @notice Computes an order's EIP-712 digest.
     * @dev Fields are `abi.encode`d individually (not the struct) so the exact 13-word preimage
     *      (type hash + 12 fields) is explicit and matches CoW's assembly implementation.
     * @param order The fully-specified order.
     * @param domainSeparator The settlement contract's EIP-712 domain separator.
     * @return orderDigest The order's EIP-712 digest.
     */
    function hash(Data memory order, bytes32 domainSeparator) internal pure returns (bytes32 orderDigest) {
        bytes32 structHash = keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                order.sellToken,
                order.buyToken,
                order.receiver,
                order.sellAmount,
                order.buyAmount,
                order.validTo,
                order.appData,
                order.feeAmount,
                order.kind,
                order.partiallyFillable,
                order.sellTokenBalance,
                order.buyTokenBalance
            )
        );
        orderDigest = keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash));
    }

    /**
     * @notice Packs a 56-byte order UID from its components.
     * @dev Layout is orderDigest(32) ‖ owner(20) ‖ validTo(4), the exact form `setPreSignature` decodes.
     * @param orderDigest The order's EIP-712 digest.
     * @param owner The order owner; must equal the `setPreSignature` caller.
     * @param validTo The order's expiry, duplicated into the UID.
     * @return orderUid The packed UID.
     */
    function packOrderUid(
        bytes32 orderDigest,
        address owner,
        uint32 validTo
    )
        internal
        pure
        returns (bytes memory orderUid)
    {
        orderUid = abi.encodePacked(orderDigest, owner, validTo);
    }

    /**
     * @notice Rescales a native token amount to 18 decimals for cross-decimal price comparison.
     * @param amount Amount in the token's native units.
     * @param decimals The token's decimals.
     * @return The amount scaled to 18 decimals.
     */
    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals <= 18) {
            return amount * (10 ** (18 - decimals));
        }
        return amount / (10 ** (decimals - 18));
    }

}
