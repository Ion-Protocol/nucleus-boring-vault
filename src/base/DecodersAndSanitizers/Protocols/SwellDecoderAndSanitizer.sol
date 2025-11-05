// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract SwellDecoderAndSanitizer is BaseDecoderAndSanitizer {

    error SwellDecoderAndSanitizer__MustWithdrawToBoringVault();

    // @desc function to claim rewards from Swell
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

    // @desc function to withdraw WSWELL, will revert if account is not the boring vault
    function withdrawTo(address account, uint256 amount) external view virtual returns (bytes memory addressesFound) {
        if (account != boringVault) {
            revert SwellDecoderAndSanitizer__MustWithdrawToBoringVault();
        }
        // nothing to sanitize
    }

    // @desc function to withdraw WSWELL by lock timestamp, check swell contract for rates, will revert if account is
    // not the boring vault
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

    // @desc function to withdraw WSWELL by multiple lock timestamps, check swell contract for rates, will revert if
    // account is not the boring vault
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
