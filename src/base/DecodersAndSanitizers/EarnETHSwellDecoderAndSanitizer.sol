// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "./BaseDecoderAndSanitizer.sol";
import { NativeWrapperDecoderAndSanitizer } from "./Protocols/NativeWrapperDecoderAndSanitizer.sol";
import { UniswapV3DecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/UniswapV3DecoderAndSanitizer.sol";
import { MasterChefV3DecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/MasterChefV3DecoderAndSanitizer.sol";
import { PendleRouterDecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/PendleRouterDecoderAndSanitizer.sol";

import { TempestDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/TempestDecoderAndSanitizer.sol";

contract EarnETHSwellDecoderAndSanitizer is
    NativeWrapperDecoderAndSanitizer,
    UniswapV3DecoderAndSanitizer,
    MasterChefV3DecoderAndSanitizer,
    PendleRouterDecoderAndSanitizer,
    TempestDecoderAndSanitizer
{
    constructor(
        address _boringVault,
        address _uniswapV3NonFungiblePositionManager
    )
        UniswapV3DecoderAndSanitizer(_uniswapV3NonFungiblePositionManager)
        BaseDecoderAndSanitizer(_boringVault)
    { }
}
