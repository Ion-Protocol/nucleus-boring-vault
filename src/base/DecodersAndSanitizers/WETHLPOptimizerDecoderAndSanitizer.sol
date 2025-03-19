// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { BaseDecoderAndSanitizer } from "./BaseDecoderAndSanitizer.sol";
import { UniswapV3DecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/UniswapV3DecoderAndSanitizer.sol";
import { BalancerV2DecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/BalancerV2DecoderAndSanitizer.sol";
import { MorphoBlueDecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/MorphoBlueDecoderAndSanitizer.sol";
import { CurveDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/CurveDecoderAndSanitizer.sol";
import { AuraDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/AuraDecoderAndSanitizer.sol";
import { ConvexDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/ConvexDecoderAndSanitizer.sol";
import { EtherFiDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/EtherFiDecoderAndSanitizer.sol";
import { NativeWrapperDecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/NativeWrapperDecoderAndSanitizer.sol";
import { OneInchDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/OneInchDecoderAndSanitizer.sol";
import { GearboxDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/GearboxDecoderAndSanitizer.sol";
import { PendleRouterDecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/PendleRouterDecoderAndSanitizer.sol";
import { AaveV3DecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/AaveV3DecoderAndSanitizer.sol";
import { AnemoyDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/AnemoyDecoderAndSanitizer.sol";
import { CircleDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/CircleDecoderAndSanitizer.sol";
import { RoosterMicroManagerDecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/RoosterMicroManagerDecoderAndSanitizer.sol";

contract WETHLPOptimizerDecoderAndSanitizer is
    AnemoyDecoderAndSanitizer,
    CircleDecoderAndSanitizer,
    MorphoBlueDecoderAndSanitizer,
    EtherFiDecoderAndSanitizer,
    NativeWrapperDecoderAndSanitizer,
    OneInchDecoderAndSanitizer,
    PendleRouterDecoderAndSanitizer,
    AaveV3DecoderAndSanitizer,
    RoosterMicroManagerDecoderAndSanitizer
{
    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) { }
    //============================== HANDLE FUNCTION COLLISIONS ===============================

    /**
     * @notice EtherFi, NativeWrapper all specify a `deposit()`,
     *         all cases are handled the same way.
     */
    function deposit()
        external
        pure
        override(EtherFiDecoderAndSanitizer, NativeWrapperDecoderAndSanitizer)
        returns (bytes memory addressesFound)
    {
        return addressesFound;
    }
}
