// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract LidoDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== LIDO ===============================

    function submit(address referral) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(referral);
    }

    // @desc wrap eth into stETH
    function wrap(uint256) external pure virtual returns (bytes memory addressesFound) {
        // Nothing to sanitize or return
        return addressesFound;
    }

    // @desc unwrap stETH into eth
    function unwrap(uint256) external pure virtual returns (bytes memory addressesFound) {
        // Nothing to sanitize or return
        return addressesFound;
    }

    // @desc request withdrawals
    // @tag owner:address:owner
    function requestWithdrawals(
        uint256[] calldata,
        address _owner
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(_owner);
    }

    // @desc claim withdrawal
    function claimWithdrawal(uint256) external pure virtual returns (bytes memory addressesFound) {
        // Nothing to sanitize or return
        return addressesFound;
    }

    // @desc claim multiple withdrawals
    function claimWithdrawals(
        uint256[] calldata,
        uint256[] calldata
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        // Nothing to sanitize or return
        return addressesFound;
    }

    function depositERC20To(
        address l1Token_,
        address l2Token_,
        address to_,
        uint256,
        uint32,
        bytes calldata
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(l1Token_, l2Token_, to_);
    }

}
