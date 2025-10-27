// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Struct encapulating an asset and an associated value.
/// @param asset Asset address.
/// @param value The associated value for this asset (e.g., amount or price).
struct AssetValue {
    IERC20 asset;
    uint256 value;
}

abstract contract AeraVaultDecoderAndSanitizer is BaseDecoderAndSanitizer {

    // @desc Deposit assets into the Aera Vault
    // @tag assets:bytes:packed bytes of every asset in each AssetValue[] input.
    function deposit(AssetValue[] memory amounts) external pure returns (bytes memory addressesFound) {
        // Requirements: check that provided amounts are sorted by asset and unique.
        for (uint256 i = 0; i < amounts.length;) {
            addressesFound = abi.encodePacked(addressesFound, amounts[i].asset);
            unchecked {
                ++i;
            }
        }
    }

    // @desc withdraw assets from the Aera Vault
    // @tag assets:bytes:packed bytes of every asset in each AssetValue[] input.
    function withdraw(AssetValue[] memory amounts) external pure returns (bytes memory amountsFound) {
        // Requirements: check that provided amounts are sorted by asset and unique.
        for (uint256 i = 0; i < amounts.length;) {
            amountsFound = abi.encodePacked(amountsFound, amounts[i].asset);
            unchecked {
                ++i;
            }
        }
    }

    // @desc Set the guardian and fee recipient for the Aera Vault as the owner, guardian can pause and manage some
    // aspects of the vault
    // @tag guardian:address:the address of the guardian
    // @tag feeRecipient:address:the address of the fee recipient
    function setGuardianAndFeeRecipient(
        address guardian,
        address feeRecipient
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(guardian, feeRecipient);
    }

    function resume() external pure returns (bytes memory addressesFound) {
        // Nothing to decode
    }

}
