// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract RenzoDecoderAndSanitizer is BaseDecoderAndSanitizer {
    function depositETH() external returns (bytes memory addressesFound) {
        // nothing to sanitize
    }

    function deposit(
        address to,
        uint256[] memory amounts,
        uint256 minLpAmount,
        uint256 deadline
    )
        external
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(to);
    }
}
