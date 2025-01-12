// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer, DecoderCustomTypes } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract TellerDecoderAndSanitizer is BaseDecoderAndSanitizer {
    //============================== ZIRCUIT SIMPLE STAKING ===============================

    function bridge(
        uint256 shareAmount,
        DecoderCustomTypes.BridgeData calldata data
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(data.chainSelector, data.destinationChainReceiver, data.bridgeFeeToken);
    }

    function deposit(
        address depositAsset,
        uint256 depositAmount,
        uint256 minimumMint
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(depositAsset);
    }

    function bulkWithdraw(
        address withdrawAsset,
        uint256 shareAmount,
        uint256 miniumAssets,
        address to
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(withdrawAsset, to);
    }
}
