// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract AuraDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== AURA ===============================

    // @desc Claim rewards from the Aura protocol
    // @tag user:address:the address of the user receiving rewards
    function getReward(address _user, bool) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_user);
    }

}
