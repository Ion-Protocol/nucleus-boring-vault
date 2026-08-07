// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import { CowSwapHelper } from "src/helper/cow-swap/CowSwapHelper.sol";

/**
 * @title CowSwapHelperDecoderAndSanitizer
 * @notice Decodes and sanitizes the vault's calls into `CowSwapHelper` for `ManagerWithMerkleVerification`.
 *         For each supported call it returns the argument values that the manager folds into the merkle leaf,
 *         so that only strategist actions matching an authorized leaf can execute.
 * @dev `CowSwapHelper` enforces a price floor on the orders it places, but it computes that floor
 *      using the `rateProvider` and `maxSlippageBps` its caller supplies.
 *
 *      `sellAmount`, `buyAmount`, and `validTo` are deliberately left unpinned, as the helper's floor check ties
 * `buyAmount` to
 *      `sellAmount` through the pinned oracle.
 */
abstract contract CowSwapHelperDecoderAndSanitizer is BaseDecoderAndSanitizer {

    // @desc Place a CoW order via CowSwapHelper. Pins the sell/buy tokens, the rate provider, and the numeric
    //       slippage bound; the per-order amounts and expiry are left free.
    // @tag sellToken:address:token the vault is selling
    // @tag buyToken:address:token the vault is buying
    // @tag rateProvider:address:oracle the price floor is derived from
    // @tag maxSlippageBps:uint256:tolerated slippage below the oracle rate, in basis points
    function placeOrder(CowSwapHelper.OrderParams calldata params) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(
            address(params.sellToken), address(params.buyToken), address(params.rateProvider), params.maxSlippageBps
        );
    }

    // @desc Cancel a previously placed CoW order.
    function cancelOrder(bytes calldata) external pure returns (bytes memory addressesFound) {
        // Nothing to decode: orderUid is an opaque hash and cancellation only clears the helper's own
        // pre-signature.
    }

    // @desc Sweep a token from the helper back to the BoringVault.
    // @tag token:address:token to sweep back to the vault
    function returnToVault(address token) external pure returns (bytes memory addressesFound) {
        // Proceeds always route to the vault (hardcoded in the helper), so pinning the token address is sufficient.
        addressesFound = abi.encodePacked(token);
    }

}
