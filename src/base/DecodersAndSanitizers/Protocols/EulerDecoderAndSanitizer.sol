// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract EulerDecoderAndSanitizer is BaseDecoderAndSanitizer {
    error EulerDecoderAndSanitizer__BoringVaultOnly();

    function enableCollateral(
        address account,
        address vault
    )
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        if (account != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();
        addressesFound = abi.encodePacked(vault);
    }

    function withdraw(
        uint256 amount,
        address receiver,
        address owner
    )
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        if (owner != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();
        if (receiver != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();
    }

    function repay(uint256 amount, address receiver) external view virtual returns (bytes memory addressesFound) {
        if (receiver != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();
    }

    function deposit(uint256 amount, address receiver) external view virtual returns (bytes memory addressesFound) {
        if (receiver != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();
    }

    function borrow(uint256 amount, address receiver) external view virtual returns (bytes memory addressesFound) {
        if (receiver != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();
    }
}
