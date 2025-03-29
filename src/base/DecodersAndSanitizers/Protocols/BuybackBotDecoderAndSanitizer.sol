// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

abstract contract BuybackBotDecoderAndSanitizer {
    function buyAndSwapEnforcingRate(address, uint256) external pure returns (bytes memory addressesFound) {
        // Nothing to sanitize
    }
}
