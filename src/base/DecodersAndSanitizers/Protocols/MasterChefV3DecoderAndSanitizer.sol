// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract MasterChefV3DecoderAndSanitizer is BaseDecoderAndSanitizer {
    function harvest(uint256, address _to) external pure virtual returns (bytes memory addressesFound) {
        return abi.encodePacked(_to);
    }

    function withdraw(uint256, address _to) external pure virtual returns (bytes memory addressesFound) {
        return abi.encodePacked(_to);
    }
}
