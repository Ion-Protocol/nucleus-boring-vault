// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseDecoderAndSanitizer } from "../BaseDecoderAndSanitizer.sol";

abstract contract ThunderheadDecoderAndSanitizer is BaseDecoderAndSanitizer {

    error ThunderheadDecoderAndSanitizer__InvalidReceiver();

    // @desc Thunderhead function to mint with community code, will revert if to is not the boring vault
    function mint(address to, string calldata communityCode) external view returns (bytes memory addressesFound) {
        if (to != boringVault) {
            revert ThunderheadDecoderAndSanitizer__InvalidReceiver();
        }
        return addressesFound;
    }

    // @desc Thunderhead function to mint, will revert if to is not the boring vault
    function mint(address to) external view returns (bytes memory addressesFound) {
        if (to != boringVault) {
            revert ThunderheadDecoderAndSanitizer__InvalidReceiver();
        }
        return addressesFound;
    }

    // @desc Thunderhead function to burn, and redeem if possible with community code, will revert if to is not the
    // boring vault
    function burnAndRedeemIfPossible(
        address to,
        uint256 amount,
        string calldata communityCode
    )
        external
        view
        returns (bytes memory addressesFound)
    {
        if (to != boringVault) {
            revert ThunderheadDecoderAndSanitizer__InvalidReceiver();
        }
        return addressesFound;
    }

    // @desc Thunderhead function to burn, and redeem if possible, will revert if to is not the boring vault
    function burnAndRedeemIfPossible(address to, uint256 amount) external view returns (bytes memory addressesFound) {
        if (to != boringVault) {
            revert ThunderheadDecoderAndSanitizer__InvalidReceiver();
        }
        return addressesFound;
    }

    // @desc Thunderhead function to redeem using a burnID
    function redeem(uint256 burnID) external pure returns (bytes memory addressesFound) {
        return addressesFound;
    }

}
