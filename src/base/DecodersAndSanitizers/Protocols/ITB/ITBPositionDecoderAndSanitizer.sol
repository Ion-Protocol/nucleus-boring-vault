/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.0;

import { BoringDecoderAndSanitizer } from "./common/BoringDecoderAndSanitizer.sol";
import { AaveDecoderAndSanitizer } from "./aave/AaveDecoderAndSanitizer.sol";
import { CurveAndConvexDecoderAndSanitizer } from "./curve_and_convex/CurveAndConvexDecoderAndSanitizer.sol";
import { GearboxDecoderAndSanitizer } from "./gearbox/GearboxDecoderAndSanitizer.sol";

contract ITBPositionDecoderAndSanitizer is
    BoringDecoderAndSanitizer,
    AaveDecoderAndSanitizer,
    CurveAndConvexDecoderAndSanitizer,
    GearboxDecoderAndSanitizer
{

    constructor(address _boringVault) BoringDecoderAndSanitizer(_boringVault) { }

    function transfer(address _to, uint256) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(_to);
    }

}
