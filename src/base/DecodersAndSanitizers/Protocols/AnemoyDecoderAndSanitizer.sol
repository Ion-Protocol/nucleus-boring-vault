// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract AnemoyDecoderAndSanitizer is BaseDecoderAndSanitizer {

    error AnemoyDecoderAndSanitizer__MustBeBoringVault();

    // @desc Request a deposit into the Anemoy Vault, will revert if controller or owner is not the boring vault
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    )
        external
        view
        returns (bytes memory addressesFound)
    {
        if (controller != boringVault || owner != boringVault) {
            revert AnemoyDecoderAndSanitizer__MustBeBoringVault();
        }

        // nothing to sanitize
    }

    // @desc Mint shares into the Anemoy Vault, will revert if controller or owner is not the boring vault
    function mint(
        uint256 shares,
        address receiver,
        address controller
    )
        external
        view
        returns (bytes memory addressesFound)
    {
        if (controller != boringVault || receiver != boringVault) {
            revert AnemoyDecoderAndSanitizer__MustBeBoringVault();
        }
        // nothing to sanitize
    }

    // @desc Request a redeem from the Anemoy Vault, will revert if controller or owner is not the boring vault
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    )
        external
        view
        returns (bytes memory addressesFound)
    {
        if (controller != boringVault || owner != boringVault) {
            revert AnemoyDecoderAndSanitizer__MustBeBoringVault();
        }
        // nothing to sanitize
    }

    // @desc Withdraw from the Anemoy Vault, will revert if controller or owner is not the boring vault
    function withdraw(
        uint256 assets,
        address receiver,
        address controller
    )
        external
        view
        returns (bytes memory addressesFound)
    {
        if (controller != boringVault || receiver != boringVault) {
            revert AnemoyDecoderAndSanitizer__MustBeBoringVault();
        }
        // nothing to sanitize
    }

}
