/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.0;

import { ITBContractDecoderAndSanitizer } from "../common/ITBContractDecoderAndSanitizer.sol";
import { CurveNoConfigDecoderAndSanitizer } from "./CurveNoConfigDecoderAndSanitizer.sol";
import { ConvexDecoderAndSanitizer } from "./ConvexDecoderAndSanitizer.sol";

/* solhint-disable */
abstract contract CurveAndConvexDecoderAndSanitizer is
    ITBContractDecoderAndSanitizer,
    CurveNoConfigDecoderAndSanitizer,
    ConvexDecoderAndSanitizer
{ }
