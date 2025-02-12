// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract ERC4626DecoderAndSanitizer is BaseDecoderAndSanitizer {
    //============================== ERC4626 ===============================

    function deposit(uint256, address receiver) external view virtual returns (bytes memory addressesFound) {
        if (receiver != boringVault) {
            revert NotVault();
        }
        addressesFound = abi.encodePacked(receiver);
    }

    function mint(uint256, address receiver) external view virtual returns (bytes memory addressesFound) {
        if (receiver != boringVault) {
            revert NotVault();
        }
        addressesFound = abi.encodePacked(receiver);
    }

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
        if (receiver != boringVault) {
            revert NotVault();
        }
        addressesFound = abi.encodePacked(receiver, owner);
    }

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
        if (receiver != boringVault) {
            revert NotVault();
        }
        addressesFound = abi.encodePacked(receiver, owner);
    }
}
