// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer, DecoderCustomTypes } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract EigenpieDecoderAndSanitizer is BaseDecoderAndSanitizer {
    //============================== ERRORS ===============================

    error EigenpieDecoderAndSanitizer__CanOnlyReceiveAsTokens();

    function userWithdrawAsset(address[] memory assets) external pure virtual returns (bytes memory addressesFound) {
        return addressesFound;
    }

    function userQueuingForWithdraw(
        address asset,
        uint256 mLRTamount
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        return addressesFound;
    }
}
