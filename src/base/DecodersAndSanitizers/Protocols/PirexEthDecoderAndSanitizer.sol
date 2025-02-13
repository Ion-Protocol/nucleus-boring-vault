// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract PirexEthDecoderAndSanitizer is BaseDecoderAndSanitizer {
    error PirexEthDecoderAndSanitizer_OnlyBoringVaultAsReceiver();

    function deposit(address receiver, bool) external returns (bytes memory) {
        if (receiver != boringVault) {
            revert PirexEthDecoderAndSanitizer_OnlyBoringVaultAsReceiver();
        }
        return abi.encodePacked(receiver);
    }

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
        return abi.encodePacked(_receiver);
    }

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
        return abi.encodePacked(_receiver);
    }

    function instantRedeemWithPxEth(uint256 _assets, address _receiver) external view returns (bytes memory) {
        if (_receiver != boringVault) {
            revert PirexEthDecoderAndSanitizer_OnlyBoringVaultAsReceiver();
        }
        return abi.encodePacked(_receiver);
    }
}
