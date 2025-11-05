// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract ZircuitSimpleStakingDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== ZIRCUIT SIMPLE STAKING ===============================

    // @desc Zircuit Simple Staking function to deposit for a user
    // @tag token:address:The token to deposit
    // @tag for:address:The user to deposit for
    function depositFor(
        address _token,
        address _for,
        uint256
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(_token, _for);
    }

    // @desc Zircuit Simple Staking function to withdraw for a user
    // @tag token:address:The token to withdraw
    function withdraw(address _token, uint256) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_token);
    }

}
