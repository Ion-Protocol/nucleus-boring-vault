// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "./BaseDecoderAndSanitizer.sol";
import { NativeWrapperDecoderAndSanitizer } from "./Protocols/NativeWrapperDecoderAndSanitizer.sol";
import { UniswapV3DecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/UniswapV3DecoderAndSanitizer.sol";
import { MasterChefV3DecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/MasterChefV3DecoderAndSanitizer.sol";
import { PendleRouterDecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/PendleRouterDecoderAndSanitizer.sol";

import { SwellDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/SwellDecoderAndSanitizer.sol";
import { CrocSwapDexDecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/CrocSwapDexDecoderAndSanitizer.sol";

import { TempestDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/TempestDecoderAndSanitizer.sol";

contract EarnETHDecoderAndSanitizer is
    NativeWrapperDecoderAndSanitizer,
    MasterChefV3DecoderAndSanitizer,
    PendleRouterDecoderAndSanitizer,
    SwellDecoderAndSanitizer,
    CrocSwapDexDecoderAndSanitizer,
    TempestDecoderAndSanitizer
{
    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) { }
}
