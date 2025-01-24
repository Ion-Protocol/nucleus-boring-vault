// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer, DecoderCustomTypes } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract MellowDecoderAndSanitizer is BaseDecoderAndSanitizer {
    //============================== ERRORS ===============================

    error MellowDecoderAndSanitizer__IncorrectRecipient();

    function withdraw(address recipient, uint256) external view virtual returns (bytes memory addressesFound) {
        if (recipient != boringVault) {
            revert MellowDecoderAndSanitizer__IncorrectRecipient();
        }

        return addressesFound;
    }

    function registerWithdrawal(
        address to,
        uint256,
        uint256[] memory,
        uint256,
        uint256,
        bool
    )
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        if (to != boringVault) {
            revert MellowDecoderAndSanitizer__IncorrectRecipient();
        }

        return addressesFound;
    }
}
