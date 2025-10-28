// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract ConvexDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== CONVEX ===============================

    // @desc Deposit into the Convex protocol
    function deposit(uint256, uint256, bool) external view virtual returns (bytes memory addressesFound) {
        // Nothing to sanitize or return
        return addressesFound;
    }

    // @desc Withdraw from the Convex protocol and unwrap the tokens
    function withdrawAndUnwrap(uint256, bool) external view virtual returns (bytes memory addressesFound) {
        // Nothing to sanitize or return
        return addressesFound;
    }

    // @desc Claim rewards from the Convex protocol
    // @tag user:address:the address of the user receiving rewards
    function getReward(address _addr, bool) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_addr);
    }

}
