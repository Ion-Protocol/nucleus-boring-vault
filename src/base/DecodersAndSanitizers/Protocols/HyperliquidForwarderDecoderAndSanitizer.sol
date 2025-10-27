// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract HyperliquidForwarderDecoderAndSanitizer is BaseDecoderAndSanitizer {

    // @desc Forward to HyperCore multisig using an EOA
    // @tag token:address:The address of the token being sent
    // @tag evmEOAToSendToAndForwardToL1:address:The address of the multisig/EOA
    function forward(
        address token,
        uint256 amount,
        address evmEOAToSendToAndForwardToL1
    )
        external
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(token, evmEOAToSendToAndForwardToL1);
    }

}
