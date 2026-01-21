// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract PirexEthDecoderAndSanitizer is BaseDecoderAndSanitizer {

    error PirexEthDecoderAndSanitizer_OnlyBoringVaultAsReceiver();

    // @desc Function to deposit ETH for pxETH, will revert if receiver is not the boring vault
    function deposit(address receiver, bool) external returns (bytes memory) {
        if (receiver != boringVault) {
            revert PirexEthDecoderAndSanitizer_OnlyBoringVaultAsReceiver();
        }
    }

    // @desc Initiate redemption by burning pxETH in return for upxETH, will revert if receiver is not the boring vault
    function initiateRedemption(
        uint256 _assets,
        address _receiver,
        bool _shouldTriggerValidatorExit
    )
        external
        view
        returns (bytes memory)
    {
        if (_receiver != boringVault) {
            revert PirexEthDecoderAndSanitizer_OnlyBoringVaultAsReceiver();
        }
    }

    // @desc function to redeem E with UPXEth, will revert if receiver is not the boring vault
    function redeemWithUpxEth(
        uint256 _tokenId,
        uint256 _assets,
        address _receiver
    )
        external
        view
        returns (bytes memory)
    {
        if (_receiver != boringVault) {
            revert PirexEthDecoderAndSanitizer_OnlyBoringVaultAsReceiver();
        }
    }

    // @desc function to redeem ETH with pxETH, will revert if receiver is not the boring vault
    function instantRedeemWithPxEth(uint256 _assets, address _receiver) external view returns (bytes memory) {
        if (_receiver != boringVault) {
            revert PirexEthDecoderAndSanitizer_OnlyBoringVaultAsReceiver();
        }
    }

}
