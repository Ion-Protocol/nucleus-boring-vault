// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract EtherFiDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== ETHERFI ===============================

    // @desc deposit into EtherFi
    function deposit() external pure virtual returns (bytes memory addressesFound) {
        // Nothing to sanitize or return
        return addressesFound;
    }

    // @desc wrap EtherFi
    function wrap(uint256) external pure virtual returns (bytes memory addressesFound) {
        // Nothing to sanitize or return
        return addressesFound;
    }

    // @desc unwrap EtherFi
    function unwrap(uint256) external pure virtual returns (bytes memory addressesFound) {
        // Nothing to sanitize or return
        return addressesFound;
    }

    // @desc request withdraw from EtherFi
    // @tag _addr:address:the address of the user requesting the withdraw
    function requestWithdraw(address _addr, uint256) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_addr);
    }

    // @desc claim withdraw from EtherFi
    // @tag _addr:address:the address of the user claiming the withdraw
    function claimWithdraw(address _addr, uint256) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_addr);
    }

}
