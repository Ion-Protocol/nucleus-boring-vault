// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import {IMaverickV2PoolLens} from "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2PoolLens.sol";
import {IMaverickV2Router} from "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2Router.sol";
import {IMaverickV2Pool} from "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2Pool.sol";
abstract contract RoosterMicroManagerDecoderAndSanitizer is BaseDecoderAndSanitizer{

    function mintPositionNftToSender(
        IMaverickV2PoolLens.AddParamsViewInputs memory addParamsViewInputs,
        uint256 deadline,
        uint256 minSqrtPrice,
        uint256 maxSqrtPrice
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(address(addParamsViewInputs.pool));
    }

    function removeLiquidity(
        IMaverickV2Pool pool,
        uint256 positionId,
        IMaverickV2Pool.RemoveLiquidityParams memory removeLiquidityParams,
        uint256 deadline,
        uint256 minSqrtPrice,
        uint256 maxSqrtPrice
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(address(pool));
    }

    function exactInputSingle(
        address recipient,
        IMaverickV2Pool pool,
        bool tokenAIn,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external pure returns (bytes memory addressesFound){
        addressesFound = abi.encodePacked(recipient, address(pool));
    }

}
