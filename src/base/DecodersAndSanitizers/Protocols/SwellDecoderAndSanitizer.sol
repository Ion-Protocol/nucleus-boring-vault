// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract SwellDecoderAndSanitizer is BaseDecoderAndSanitizer {
    error SwellDecoderAndSanitizer__MustWithdrawToBoringVault();

    function claim(
        address[] calldata,
        address[] calldata,
        uint256[] calldata,
        bytes32[][] calldata
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        // nothing to sanitize
    }

    function withdrawTo(address account, uint256 amount) external view virtual returns (bytes memory addressesFound) {
        if (account != boringVault) {
            revert SwellDecoderAndSanitizer__MustWithdrawToBoringVault();
        }
        // nothing to sanitize
    }

    function withdrawToByLockTimestamp(
        address account,
        uint256 lockTimestamp,
        bool allowRemainderLoss
    )
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        if (account != boringVault) {
            revert SwellDecoderAndSanitizer__MustWithdrawToBoringVault();
        }
        // nothing to sanitize
    }

    function withdrawToByLockTimestamps(
        address account,
        uint256[] calldata lockTimestamp,
        bool allowRemainderLoss
    )
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        if (account != boringVault) {
            revert SwellDecoderAndSanitizer__MustWithdrawToBoringVault();
        }
        // nothing to sanitize
    }
}
