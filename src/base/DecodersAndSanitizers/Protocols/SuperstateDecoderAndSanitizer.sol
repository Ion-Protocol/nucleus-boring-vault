// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract SuperstateDecoderAndSanitizer is BaseDecoderAndSanitizer {

    // @desc deposit into USTB
    // @tag to:address:USTB receiver
    // @tag stablecoin:address:deposit asset
    function subscribe(address to, uint256, address stablecoin) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(to, stablecoin);
    }

}
