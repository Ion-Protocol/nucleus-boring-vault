/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.0;

import { BaseDecoderAndSanitizer } from "./BaseDecoderAndSanitizer.sol";

contract rariETHRariDecoderAndSanitizer is BaseDecoderAndSanitizer {
    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) { }

    function transfer(address _to, uint256) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_to);
    }
}
