// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract PirexEthDecoderAndSanitizer is BaseDecoderAndSanitizer {
    function deposit(address receiver, bool) external returns (bytes memory) {
        return abi.encodePacked(receiver);
    }
}
