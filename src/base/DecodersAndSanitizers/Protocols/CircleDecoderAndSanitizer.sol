// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract CircleDecoderAndSanitizer is BaseDecoderAndSanitizer {

    // @desc Deposit assets into Circle TokenMessengerV1 to burn, in order to bridge to another chain
    // @tag destinationDomain:uint32:the id of the destination chain
    // @tag mintRecipient:bytes32:the address of the recipient on the destination chain in a bytes32 format
    // @tag burnToken:address:the address of the token to burn
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    )
        external
        view
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(destinationDomain, mintRecipient, burnToken);
    }

    // @desc Deposit assets into Circle TokenMessengerV2 to burn, in order to bridge to another chain
    // @tag destinationDomain:uint32:the id of the destination chain
    // @tag mintRecipient:bytes32:the address of the recipient on the destination chain in a bytes32 format
    // @tag burnToken:address:the address of the token to burn
    // @tag destinationCaller:bytes32:the address as bytes32 which can call receiveMessage on destination domain. If set
    // to bytes32(0), any address can call receiveMessage @tag maxFee:uint256:Max fee paid for fast burn, specified in
    // units of burnToken
    // @tag minFinalityThreshold:uint32:Minimum finality threshold at which burn will be attested
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    )
        external
        view
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(
            destinationDomain, mintRecipient, burnToken, destinationCaller, maxFee, minFinalityThreshold
        );
    }

    // @desc Receive a message from Circle, in order to mint tokens on the destination chain
    function receiveMessage(
        bytes memory message,
        bytes memory attestation
    )
        external
        view
        returns (bytes memory addressesFound)
    {
        // nothing to sanitize
        return addressesFound;
    }

}
