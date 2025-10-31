// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract SwellSimpleStakingDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== SWELL SIMPLE STAKING ===============================

    // @desc function to deposit into Swell Simple Staking
    // @tag token:address:The token to deposit
    // @tag receiver:address:The receiver of the tokens
    function deposit(
        address _token,
        uint256,
        address _receiver
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(_token, _receiver);
    }

    // @desc function to withdraw from Swell Simple Staking, will revert if receiver is not the boring vault
    // @tag token:address:The token to withdraw
    // @tag receiver:address:The receiver of the tokens
    function withdraw(
        address _token,
        uint256,
        address _receiver
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(_token, _receiver);
    }

}
