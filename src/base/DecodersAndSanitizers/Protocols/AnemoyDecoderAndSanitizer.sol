// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract AnemoyDecoderAndSanitizer is BaseDecoderAndSanitizer {
    error AnemoyDecoderAndSanitizer__MustBeBoringVault();

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
