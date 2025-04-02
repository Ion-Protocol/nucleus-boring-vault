// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer, DecoderCustomTypes } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract VelodromeBuybackDecoderAndSanitizer is BaseDecoderAndSanitizer {
    function buyAndSwapEnforcingRate(address, uint256) external pure returns (bytes memory addressesFound) {
        // Nothing to sanitize
    }
}
