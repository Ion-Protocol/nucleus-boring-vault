// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {
    BaseDecoderAndSanitizer,
    DecoderCustomTypes
} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract MellowDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== ERRORS ===============================

    error MellowDecoderAndSanitizer__IncorrectRecipient();

    // @desc withdraw, will revert if the recipient is not the boring vault
    function withdraw(address recipient, uint256) external view virtual returns (bytes memory addressesFound) {
        if (recipient != boringVault) {
            revert MellowDecoderAndSanitizer__IncorrectRecipient();
        }

        return addressesFound;
    }

    // @desc withdraw, will revert if the receiver is not the boring vault
    function withdraw(uint256, address receiver, address) external view virtual returns (bytes memory addressesFound) {
        if (receiver != boringVault) {
            revert MellowDecoderAndSanitizer__IncorrectRecipient();
        }

        return addressesFound;
    }

    // @desc registerWithdrawal, will revert if the to address is not the boring vault
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

    // @desc claim, will revert if the recipient is not the boring vault
    function claim(address, address recipient, uint256) external view virtual returns (bytes memory addressesFound) {
        if (recipient != boringVault) {
            revert MellowDecoderAndSanitizer__IncorrectRecipient();
        }
        return addressesFound;
    }

}
