// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract PumpBTCDecoderAndSanitizer is BaseDecoderAndSanitizer {
    //============================== PumpBTC ===============================

    function stake(uint256 amount) external pure virtual returns (bytes memory addressesFound) {
        // nothing to sanitize
    }

    function unstakeInstant(uint256 amount) external pure virtual returns (bytes memory addressFound) {
        // nothing to sanitize
    }
}
