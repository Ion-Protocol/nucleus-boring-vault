// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import {
    PendleRouterDecoderAndSanitizer,
    BaseDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/Protocols/PendleRouterDecoderAndSanitizer.sol";
import { PumpBTCDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/PumpBTCDecoderAndSanitizer.sol";
import { swBTCDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/swBTCDecoderAndSanitizer.sol";
import { UniswapV3DecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/UniswapV3DecoderAndSanitizer.sol";
import { OneInchDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/OneInchDecoderAndSanitizer.sol";
import { BalancerV2DecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/BalancerV2DecoderAndSanitizer.sol";
import { CurveDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/CurveDecoderAndSanitizer.sol";

contract earnBTCDecoderAndSanitizer is
    PendleRouterDecoderAndSanitizer,
    PumpBTCDecoderAndSanitizer,
    swBTCDecoderAndSanitizer,
    UniswapV3DecoderAndSanitizer,
    OneInchDecoderAndSanitizer,
    BalancerV2DecoderAndSanitizer,
    CurveDecoderAndSanitizer
{
    constructor(
        address _boringVault,
        address _uniswapV3NonFungiblePositionManager
    )
        UniswapV3DecoderAndSanitizer(_uniswapV3NonFungiblePositionManager)
        BaseDecoderAndSanitizer(_boringVault)
    { }

    function deposit(
        uint256,
        address receiver
    )
        external
        pure
        override(BalancerV2DecoderAndSanitizer, swBTCDecoderAndSanitizer, CurveDecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(receiver);
    }

    function withdraw(uint256)
        external
        pure
        override(BalancerV2DecoderAndSanitizer, CurveDecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        // Nothing to sanitize or return
        return addressesFound;
    }
}
