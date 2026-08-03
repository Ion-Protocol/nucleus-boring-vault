// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract CoWProtocolDecoderAndSanitizer is BaseDecoderAndSanitizer {

    // @desc preSign an order as a smart contract for CoW protocol. Allows both signing and revoking signature
    function setPreSignature(bytes calldata orderUid, bool signed) external pure returns (bytes memory addressesFound) {
        // Nothing to decode
    }

}
