// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract ERC4626DecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== ERC4626 ===============================

    // @desc deposit into the ERC4626 vault
    // @tag receiver:address:the address of the receiver of the vault tokens
    function deposit(uint256, address receiver) external view virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(receiver);
    }

    // @desc mint tokens from the ERC4626 vault
    // @tag receiver:address:the address of the receiver of the vault tokens
    function mint(uint256, address receiver) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(receiver);
    }

    // @desc withdraw tokens from the ERC4626 vault
    // @tag receiver:address:the address of the receiver of the vault tokens
    // @tag owner:address:the address of the owner of the vault tokens
    function withdraw(
        uint256,
        address receiver,
        address owner
    )
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(receiver, owner);
    }

    // @desc redeem tokens from the ERC4626 vault
    // @tag receiver:address:the address of the receiver of the vault tokens
    // @tag owner:address:the address of the owner of the vault tokens
    function redeem(
        uint256,
        address receiver,
        address owner
    )
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(receiver, owner);
    }

}
