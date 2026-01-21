// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {
    BaseDecoderAndSanitizer,
    DecoderCustomTypes
} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract OneInchDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== ERRORS ===============================

    error OneInchDecoderAndSanitizer__PermitNotSupported();

    //============================== ONEINCH ===============================

    // @desc swap tokens with 1inch, will revert if the permit is not empty
    // @tag executor:address:executor
    // @tag srcToken:address:source token
    // @tag dstToken:address:destination token
    // @tag srcReceiver:address:source receiver
    // @tag dstReceiver:address:destination receiver
    function swap(
        address executor,
        DecoderCustomTypes.SwapDescription calldata desc,
        bytes calldata permit,
        bytes calldata
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        if (permit.length > 0) revert OneInchDecoderAndSanitizer__PermitNotSupported();
        addressesFound = abi.encodePacked(executor, desc.srcToken, desc.dstToken, desc.srcReceiver, desc.dstReceiver);
    }

    // @desc use uniswapV3Swap on OneInch
    // @tag packedArgs:bytes:packed arguments
    function uniswapV3Swap(
        uint256,
        uint256,
        uint256[] calldata pools
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        for (uint256 i; i < pools.length; ++i) {
            addressesFound = abi.encodePacked(addressesFound, uint160(pools[i]));
        }
    }

}
