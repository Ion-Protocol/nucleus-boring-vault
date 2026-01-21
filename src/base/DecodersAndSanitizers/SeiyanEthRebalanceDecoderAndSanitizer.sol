// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import { PirexEthDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/PirexEthDecoderAndSanitizer.sol";
import {
    LayerZeroOFTDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/Protocols/LayerZeroOFTDecoderAndSanitizer.sol";
import {
    NativeWrapperDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/Protocols/NativeWrapperDecoderAndSanitizer.sol";
import { ERC4626DecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/ERC4626DecoderAndSanitizer.sol";
import { CurveDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/CurveDecoderAndSanitizer.sol";

contract SeiyanEthRebalanceDecoderAndSanitizer is
    BaseDecoderAndSanitizer,
    PirexEthDecoderAndSanitizer,
    LayerZeroOFTDecoderAndSanitizer,
    NativeWrapperDecoderAndSanitizer,
    ERC4626DecoderAndSanitizer,
    CurveDecoderAndSanitizer
{

    error SeiyanEthRebalanceDecoderAndSanitizer_OnlyBoringVaultAsReceiver();

    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) { }

    function deposit(
        uint256,
        address receiver
    )
        external
        view
        override(CurveDecoderAndSanitizer, ERC4626DecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        if (receiver != boringVault) {
            revert SeiyanEthRebalanceDecoderAndSanitizer_OnlyBoringVaultAsReceiver();
        }
        addressesFound = abi.encodePacked(receiver);
    }

    /**
     * @notice Curve and WETH both specifies a `withdraw(uint256)`, but all
     * cases are handled the same way.
     */
    function withdraw(uint256)
        external
        pure
        override(CurveDecoderAndSanitizer, NativeWrapperDecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        // Nothing to sanitize or return
        return addressesFound;
    }

}
