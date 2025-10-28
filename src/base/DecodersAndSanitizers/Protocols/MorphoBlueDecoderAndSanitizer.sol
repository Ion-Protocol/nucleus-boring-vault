// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {
    BaseDecoderAndSanitizer,
    DecoderCustomTypes
} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract MorphoBlueDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== ERRORS ===============================

    error MorphoBlueDecoderAndSanitizer__CallbackNotSupported();

    //============================== MORPHO BLUE ===============================

    // @desc supply to morpho blue, will revert if the data is not empty
    // @tag loanToken:address
    // @tag collateralToken:address
    // @tag oracle:address
    // @tag irm:address
    // @tag onBehalf:address:on behalf of the user
    function supply(
        DecoderCustomTypes.MarketParams calldata params,
        uint256,
        uint256,
        address onBehalf,
        bytes calldata data
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        // Sanitize raw data
        if (data.length > 0) revert MorphoBlueDecoderAndSanitizer__CallbackNotSupported();
        // Return addresses found
        addressesFound = abi.encodePacked(params.loanToken, params.collateralToken, params.oracle, params.irm, onBehalf);
    }

    // @desc withdraw from morpho blue
    // @tag loanToken:address
    // @tag collateralToken:address
    // @tag oracle:address
    // @tag irm:address
    // @tag onBehalf:address:on behalf of the user
    // @tag receiver:address:receiver of the withdrawn tokens
    function withdraw(
        DecoderCustomTypes.MarketParams calldata params,
        uint256,
        uint256,
        address onBehalf,
        address receiver
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        // Nothing to sanitize
        // Return addresses found
        addressesFound =
            abi.encodePacked(params.loanToken, params.collateralToken, params.oracle, params.irm, onBehalf, receiver);
    }

    // @desc borrow from morpho blue
    // @tag loanToken:address
    // @tag collateralToken:address
    // @tag oracle:address
    // @tag irm:address
    // @tag onBehalf:address:on behalf of the user
    // @tag receiver:address:receiver of the borrowed tokens
    function borrow(
        DecoderCustomTypes.MarketParams calldata params,
        uint256,
        uint256,
        address onBehalf,
        address receiver
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound =
            abi.encodePacked(params.loanToken, params.collateralToken, params.oracle, params.irm, onBehalf, receiver);
    }

    // @desc repay a borrow from morpho blue, will revert if the data is not empty
    // @tag loanToken:address
    // @tag collateralToken:address
    // @tag oracle:address
    // @tag irm:address
    // @tag onBehalf:address:on behalf of the user
    function repay(
        DecoderCustomTypes.MarketParams calldata params,
        uint256,
        uint256,
        address onBehalf,
        bytes calldata data
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        // Sanitize raw data
        if (data.length > 0) revert MorphoBlueDecoderAndSanitizer__CallbackNotSupported();

        // Return addresses found
        addressesFound = abi.encodePacked(params.loanToken, params.collateralToken, params.oracle, params.irm, onBehalf);
    }

    // @desc supply collateral to morpho blue, will revert if the data is not empty
    // @tag loanToken:address
    // @tag collateralToken:address
    // @tag oracle:address
    // @tag irm:address
    // @tag onBehalf:address:on behalf of the user
    function supplyCollateral(
        DecoderCustomTypes.MarketParams calldata params,
        uint256,
        address onBehalf,
        bytes calldata data
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        // Sanitize raw data
        if (data.length > 0) revert MorphoBlueDecoderAndSanitizer__CallbackNotSupported();

        // Return addresses found
        addressesFound = abi.encodePacked(params.loanToken, params.collateralToken, params.oracle, params.irm, onBehalf);
    }

    // @desc withdraw collateral from morpho blue
    // @tag loanToken:address
    // @tag collateralToken:address
    // @tag oracle:address
    // @tag irm:address
    // @tag onBehalf:address:on behalf of the user
    // @tag receiver:address:receiver of the withdrawn tokens
    function withdrawCollateral(
        DecoderCustomTypes.MarketParams calldata params,
        uint256,
        address onBehalf,
        address receiver
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        // Nothing to sanitize
        // Return addresses found
        addressesFound =
            abi.encodePacked(params.loanToken, params.collateralToken, params.oracle, params.irm, onBehalf, receiver);
    }

}
