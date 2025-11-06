// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {
    BaseDecoderAndSanitizer,
    DecoderCustomTypes
} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract VelodromeBuybackDecoderAndSanitizer is BaseDecoderAndSanitizer {

    // @desc buyAndSwapEnforcingRate using the VelodromeBuyback micromanager
    // @tag quoteAsset:address:quoteAsset to swap for vault asset
    function buyAndSwapEnforcingRate(address quoteAsset, uint256) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(quoteAsset);
    }

}
