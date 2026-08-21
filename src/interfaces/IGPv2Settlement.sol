// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title IGPv2Settlement
 * @notice Minimal interface for CoW Protocol's settlement contract, exposing only the surface the CowSwap
 *         helper uses: the pre-signature entrypoint and the two immutables needed to reconstruct an order's
 *         UID on-chain.
 * @dev `setPreSignature` requires `owner == msg.sender`, where `owner` is the account embedded in
 *      `orderUid`. That single constraint is what forces the caller of `setPreSignature` to be the same
 *      account whose sell-token balance and approval the relayer draws from at settlement.
 */
interface IGPv2Settlement {

    /**
     * @notice Sets or clears the on-chain pre-signature authorizing `orderUid` for settlement.
     * @dev Reverts unless the `owner` packed into `orderUid` equals `msg.sender`.
     * @param orderUid 56-byte packed UID: orderDigest(32) ‖ owner(20) ‖ validTo(4).
     * @param signed True to authorize the order, false to revoke (cancel) it.
     */
    function setPreSignature(bytes calldata orderUid, bool signed) external;

    /**
     * @notice Cumulative amount of an order already settled, keyed by its packed UID.
     * @dev For the sell orders this helper places, the value is denominated in sell-token units and never
     *      exceeds the order's `sellAmount`. Read on cancellation to compute the unfilled remainder to refund.
     * @param orderUid The 56-byte packed order UID.
     * @return The amount filled so far.
     */
    function filledAmount(bytes calldata orderUid) external view returns (uint256);

    /**
     * @notice The EIP-712 domain separator this settlement contract signs orders under.
     */
    function domainSeparator() external view returns (bytes32);

    /**
     * @notice The relayer that actually pulls sell tokens from order owners; the address that must be
     *         granted the sell-token approval.
     */
    function vaultRelayer() external view returns (address);

}
