// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract RenzoDecoderAndSanitizer is BaseDecoderAndSanitizer {

    // @desc function to deposit ETH for pzETH
    function depositETH() external returns (bytes memory addressesFound) {
        // nothing to sanitize
        return addressesFound;
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
