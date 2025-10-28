// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import {
    BaseDecoderAndSanitizer,
    DecoderCustomTypes
} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Struct encapulating an asset and an associated value.
/// @param asset Asset address.
/// @param value The associated value for this asset (e.g., amount or price).
struct AssetValue {
    IERC20 asset;
    uint256 value;
}

abstract contract MorphoPositionOracleDecoderAndSanitizer is BaseDecoderAndSanitizer {

    function setMarkets(DecoderCustomTypes.MarketData[] calldata markets_)
        external
        pure
        returns (bytes memory addressesFound)
    {
        for (uint256 i = 0; i < markets_.length;) {
            addressesFound =
                abi.encodePacked(addressesFound, markets_[i].id, markets_[i].priceFeed, markets_[i].invertPrice);
            unchecked {
                ++i;
            }
        }
    }

}
