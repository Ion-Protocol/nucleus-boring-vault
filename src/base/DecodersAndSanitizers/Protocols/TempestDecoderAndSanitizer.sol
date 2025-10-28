// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract TempestDecoderAndSanitizer is BaseDecoderAndSanitizer {

    error TempestDecoderAndSanitizer__CheckSlippageRequired();

    // @desc function to deposit into Tempest, will revert if checkSlippage is false
    // @tag receiver:address:The receiver of the tokens
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

    // @desc function to deposit ETH for Tempest
    // @tag receiver:address:The receiver of the tokens
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

    // @desc Tempest function to redeem without swap, will revert if checkSlippage is false
    // @tag receiver:address:The receiver of the tokens
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

    // @desc Tempest function to deposit multiple tokens, will revert if checkSlippage is false
    // @tag receiver:address:The receiver of the tokens
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

    // @desc Tempest function to redeem, will revert if checkSlippage is false
    // @tag receiver:address:The receiver of the tokens
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

    // @desc Tempest function to redeem with ETH
    // @tag receiver:address:The receiver of the tokens
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
