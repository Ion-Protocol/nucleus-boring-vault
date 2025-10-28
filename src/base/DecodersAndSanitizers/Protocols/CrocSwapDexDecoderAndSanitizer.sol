// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract CrocSwapDexDecoderAndSanitizer is BaseDecoderAndSanitizer {

    // @desc Swap tokens in the CrocSwap (Ambient) protocol
    // @tag base:address:the address of the base token
    // @tag quote:address:the address of the quote token
    function swap(
        address base,
        address quote,
        uint256 poolIdx,
        bool isBuy,
        bool inBaseQty,
        uint128 qty,
        uint16 tip,
        uint128 limitPrice,
        uint128 minOut,
        uint8 reserveFlags
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(base, quote);
    }

}
