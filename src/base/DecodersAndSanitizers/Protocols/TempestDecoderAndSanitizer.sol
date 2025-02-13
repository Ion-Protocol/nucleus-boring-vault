// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract TempestDecoderAndSanitizer is BaseDecoderAndSanitizer {
    error TempestDecoderAndSanitizer__CheckSlippageRequired();

    function deposit(
        uint256 amount,
        address receiver,
        bool checkSlippage
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        if (checkSlippage) {
            addressesFound = abi.encodePacked(receiver);
        } else {
            revert TempestDecoderAndSanitizer__CheckSlippageRequired();
        }
    }

    // deposit with ETH
    function deposit(
        uint256 amount,
        address receiver,
        bytes memory merkleProofs
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(receiver);
    }

    function redeemWithoutSwap(
        uint256 shares,
        address receiver,
        address owner,
        bool checkSlippage
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        if (checkSlippage) {
            addressesFound = abi.encodePacked(receiver);
        } else {
            revert TempestDecoderAndSanitizer__CheckSlippageRequired();
        }
    }

    function deposits(
        uint256[] calldata amounts,
        address receiver,
        bool checkSlippage
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        if (checkSlippage) {
            addressesFound = abi.encodePacked(receiver);
        } else {
            revert TempestDecoderAndSanitizer__CheckSlippageRequired();
        }
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minimumReceive,
        bool checkSlippage
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        if (checkSlippage) {
            addressesFound = abi.encodePacked(receiver);
        } else {
            revert TempestDecoderAndSanitizer__CheckSlippageRequired();
        }
    }

    // redeem with ETH
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        bytes memory merkleProofs
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(receiver);
    }
}
