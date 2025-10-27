// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract FlashHypeDecoderAndSanitizer is BaseDecoderAndSanitizer {

    // @desc stake into flash hype, no community code
    function stake(address asset) external pure returns (bytes memory addressesFound) {
        // nothing to decode
    }

    // @desc unstake from flash hype, no community code
    function unstake(uint256) external pure returns (bytes memory addressesFound) {
        // nothing to decode
    }

}
