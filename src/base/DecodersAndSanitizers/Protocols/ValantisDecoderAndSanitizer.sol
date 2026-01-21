// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {
    BaseDecoderAndSanitizer,
    DecoderCustomTypes
} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract ValantisDecoderAndSanitizer is BaseDecoderAndSanitizer {

    function swap(DecoderCustomTypes.SovereignPoolSwapParams calldata params)
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound =
            abi.encodePacked(params.isSwapCallback, params.isZeroToOne, params.recipient, params.swapTokenOut);
    }

}
