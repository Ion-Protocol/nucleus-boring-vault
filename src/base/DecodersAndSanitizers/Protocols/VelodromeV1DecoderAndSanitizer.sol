// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import { DecoderCustomTypes } from "src/interfaces/DecoderCustomTypes.sol";

abstract contract VelodromeV1DecoderAndSanitizer is BaseDecoderAndSanitizer {
    error VelodromeV1DecoderAndSanitizer__BadToAddress();

    // @desc velodrome v1 swap exact tokens for tokens with a single route
    // @tag tokenFrom:address
    // @tag tokenTo:address
    function swapExactTokensForTokensSimple(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address to,
        uint256 deadline
    )
        external
        returns (bytes memory addressesFound)
    {
        if (to != boringVault) revert VelodromeV1DecoderAndSanitizer__BadToAddress();

        addressesFound = abi.encodePacked(tokenFrom, tokenTo);
    }

    // @desc velodrome v1 swap exact tokens for tokens with multiple routes
    // @tag tokenFrom:address
    // @tag tokenTo:address
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        DecoderCustomTypes.route[] calldata routes,
        address to,
        uint256 deadline
    )
        external
        returns (bytes memory addressesFound)
    {
        if (to != boringVault) revert VelodromeV1DecoderAndSanitizer__BadToAddress();

        for (uint256 i; i < routes.length; ++i) {
            addressesFound = abi.encodePacked(addressesFound, routes[i].from, routes[i].to);
        }
    }
}
