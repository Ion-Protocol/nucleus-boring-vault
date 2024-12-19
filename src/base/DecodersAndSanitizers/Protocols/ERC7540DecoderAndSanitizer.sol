// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC4626DecoderAndSanitizer } from "src/base/DecodersAndSanitizers/ERC4626DecoderAndSanitizer.sol";

abstract contract ERC4626DecoderAndSanitizer is ERC4626DecoderAndSanitizer {
    //============================== ERC7540 ===============================

    function requestDeposit(
        uint256,
        address controller,
        address owner
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(controller, owner);
    }

    function requestRedeem(
        uint256,
        address controller,
        address owner
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(controller, owner);
    }
}
