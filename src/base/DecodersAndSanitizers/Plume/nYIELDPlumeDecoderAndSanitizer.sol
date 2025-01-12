// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "../BaseDecoderAndSanitizer.sol";
import { TellerDecoderAndSanitizer } from "../Protocols/TellerDecoderAndSanitizer.sol";
import { LayerZeroOFTDecoderAndSanitizer } from "../Protocols/LayerZeroOFTDecoderAndSanitizer.sol";

contract nYIELDPlumeDecoderAndSanitizer is TellerDecoderAndSanitizer, LayerZeroOFTDecoderAndSanitizer {
    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) { }
}
