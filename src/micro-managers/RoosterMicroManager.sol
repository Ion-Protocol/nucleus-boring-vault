// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IMaverickV2Pool } from "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2Pool.sol";
import { IMaverickV2LiquidityManager } from
    "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2LiquidityManager.sol";
import { IMaverickV2PoolLens } from "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2PoolLens.sol";
import { IMaverickV2Quoter } from "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2Quoter.sol";
import { IMaverickV2Position } from "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2Position.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RoosterMicroManager
 * @notice This contract is a "micro manager" for the Rooster protocol. To help with decoding and sanitizing Rooster
 * actions
 * @custom:security-contact security@molecularlabs.io
 */
contract RoosterMicroManager is Ownable {
    IMaverickV2PoolLens public immutable poolLens;
    IMaverickV2LiquidityManager public immutable liquidityManager;
    IMaverickV2Quoter public immutable quoter;

    constructor(address payable _liquidityManager, address _poolLens, address _quoter) Ownable(msg.sender) {
        liquidityManager = IMaverickV2LiquidityManager(_liquidityManager);
        poolLens = IMaverickV2PoolLens(_poolLens);
        quoter = IMaverickV2Quoter(_quoter);
    }

    function dustCollector(IERC20 token) external onlyOwner {
        token.transfer(owner(), token.balanceOf(address(this)));
    }

    function mintPositionNftToSender(
        IMaverickV2PoolLens.AddParamsViewInputs memory addParamsViewInputs,
        uint256 deadline,
        uint256 minSqrtPrice,
        uint256 maxSqrtPrice
    )
        external
        payable
        returns (uint256)
    {
        IMaverickV2Pool pool = addParamsViewInputs.pool;
        IERC20 tokenA = pool.tokenA();
        IERC20 tokenB = pool.tokenB();

        // get addLiquidity params
        (
            bytes memory packedSqrtPriceBreaks,
            bytes[] memory packedArgs,
            ,
            IMaverickV2Pool.AddLiquidityParams[] memory addParams,
        ) = poolLens.getAddLiquidityParams(addParamsViewInputs);

        // calculate the exact amounts of liquidity to add
        // we use the first addParam as we plan not to use price breaks
        // addParams length = numPriceBreaks * 2 + 1
        (uint256 amountA, uint256 amountB,) = quoter.calculateAddLiquidity(pool, addParams[0]);

        _transferAndApproveTokens(tokenA, tokenB, amountA, amountB);

        // check deadline and sqrt price
        liquidityManager.checkDeadline(deadline);
        liquidityManager.checkSqrtPrice(pool, minSqrtPrice, maxSqrtPrice);

        // mint position nft
        (,,, uint256 tokenId) = liquidityManager.mintPositionNft(pool, msg.sender, packedSqrtPriceBreaks, packedArgs);

        return tokenId;
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
    {
        IMaverickV2Position maverickPosition = liquidityManager.position();
        maverickPosition.transferFrom(msg.sender, address(this), positionId);

        maverickPosition.checkDeadline(deadline);
        maverickPosition.checkSqrtPrice(pool, minSqrtPrice, maxSqrtPrice);
        (uint256 tokenAAmount, uint256 tokenBAmount) =
            maverickPosition.removeLiquidity(positionId, msg.sender, pool, removeLiquidityParams);
    }

    function _transferAndApproveTokens(IERC20 tokenA, IERC20 tokenB, uint256 amountA, uint256 amountB) internal {
        if (amountA > 0) {
            tokenA.transferFrom(msg.sender, address(this), amountA);
            tokenA.approve(address(liquidityManager), amountA);
        }
        if (amountB > 0) {
            tokenB.transferFrom(msg.sender, address(this), amountB);
            tokenB.approve(address(liquidityManager), amountB);
        }
    }
}
