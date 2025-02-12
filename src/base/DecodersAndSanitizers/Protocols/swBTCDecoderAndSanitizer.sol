// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract swBTCDecoderAndSanitizer is BaseDecoderAndSanitizer {
    //============================== swBTCDecoderAndSanitizer ===============================

    error swBTCDecoderAndSanitizer_ThirdPartyNotSupported();

    function deposit(uint256, address receiver) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(receiver);
    }

    function requestWithdraw(
        address asset,
        uint96 shares,
        uint16 maxLoss,
        bool allowThirdPartyToComplete
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        if (allowThirdPartyToComplete) {
            revert swBTCDecoderAndSanitizer_ThirdPartyNotSupported();
        }
        addressesFound = abi.encodePacked(asset);
    }
}
