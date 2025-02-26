// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseDecoderAndSanitizer } from "../BaseDecoderAndSanitizer.sol";

abstract contract ThunderheadDecoderAndSanitizer is BaseDecoderAndSanitizer {
    error ThunderheadDecoderAndSanitizer__InvalidReceiver();

    function mint(address to, string calldata communityCode) external view returns (bytes memory addressesFound) {
        if (to != boringVault) {
            revert ThunderheadDecoderAndSanitizer__InvalidReceiver();
        }
        return addressesFound;
    }

    function mint(address to) external view returns (bytes memory addressesFound) {
        if (to != boringVault) {
            revert ThunderheadDecoderAndSanitizer__InvalidReceiver();
        }
        return addressesFound;
    }

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

    function burnAndRedeemIfPossible(address to, uint256 amount) external view returns (bytes memory addressesFound) {
        if (to != boringVault) {
            revert ThunderheadDecoderAndSanitizer__InvalidReceiver();
        }
        return addressesFound;
    }

    function redeem(uint256 burnID) external pure returns (bytes memory addressesFound) {
        return addressesFound;
    }
}
