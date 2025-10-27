// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract swBTCDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== swBTCDecoderAndSanitizer ===============================

    error swBTCDecoderAndSanitizer_ThirdPartyNotSupported();

    // @desc function to deposit to swBTC, decode the receiver address only (likely boringVault)
    // @tag receiver:address
    function deposit(uint256, address receiver) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(receiver);
    }

    // @desc function to claim the withdraw of WBTC from swBTC withdraw queue, decode the asset (WBTC) and the account
    // (boringVault)
    // @tag asset:address
    // @tag account:address
    function completeWithdraw(
        address asset,
        address account,
        uint256
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(asset, account);
    }

    // @desc function to request the withdraw of WBTC from swBTC withdraw queue, decode the asset (WBTC)
    // @tag asset:address
    function requestWithdraw(
        address asset,
        uint96 shares,
        bool allowThirdPartyToComplete
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        if (allowThirdPartyToComplete) {
            revert swBTCDecoderAndSanitizer_ThirdPartyNotSupported();
        }
        addressesFound = abi.encodePacked(asset);
    }

}
