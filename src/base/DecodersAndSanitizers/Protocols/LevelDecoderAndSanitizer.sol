// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {
    BaseDecoderAndSanitizer,
    DecoderCustomTypes
} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

enum OrderType {
    MINT,
    REDEEM
}

struct Order {
    OrderType order_type;
    address benefactor;
    address beneficiary;
    address collateral_asset;
    uint256 collateral_amount;
    uint256 lvlusd_amount;
}

abstract contract LevelDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== ERRORS ===============================

    error LevelDecoderAndSanitizer__BoringVaultOnly();

    //============================== LEVEL FINANCE ===============================
    // @desc mintDefault, will revert if the benefactor or beneficiary is not the boring vault
    // @tag collateral_asset:address:collateral asset
    function mintDefault(Order calldata order) external view returns (bytes memory addressesFound) {
        if (order.benefactor == boringVault && order.beneficiary == boringVault) {
            addressesFound = abi.encodePacked(order.collateral_asset);
        } else {
            revert LevelDecoderAndSanitizer__BoringVaultOnly();
        }
    }

    // @desc initiateRedeem, if no immediate liquidity, will revert if the benefactor or beneficiary is not the boring
    // vault
    // @tag collateral_asset:address:collateral asset
    function initiateRedeem(Order calldata order) external view returns (bytes memory addressesFound) {
        if (order.benefactor == boringVault && order.beneficiary == boringVault) {
            addressesFound = abi.encodePacked(order.collateral_asset);
        } else {
            revert LevelDecoderAndSanitizer__BoringVaultOnly();
        }
    }

    // @desc redeem, will revert if the benefactor or beneficiary is not the boring vault
    // @tag collateral_asset:address:collateral asset
    function redeem(Order calldata order) external view returns (bytes memory addressesFound) {
        if (order.benefactor == boringVault && order.beneficiary == boringVault) {
            addressesFound = abi.encodePacked(order.collateral_asset);
        } else {
            revert LevelDecoderAndSanitizer__BoringVaultOnly();
        }
    }
    // @desc complete an initiated redeem

    function completeRedeem(address token) external pure returns (bytes memory addressesFound) {
        return addressesFound;
    }

}
