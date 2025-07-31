// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IUniswapV3SwapCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { SafeCast } from "@uniswap/v3-core/contracts/libraries/SafeCast.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { console } from "forge-std/console.sol";

library TickMath {
    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;
}

interface IHyperswapV3SwapCallback {
    function hyperswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

contract LHYPEDeleverage is IHyperswapV3SwapCallback {
    using SafeCast for uint256;

    IPool public hypurrfiPool = IPool(0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b);
    IUniswapV3Pool public hyperswapPool = IUniswapV3Pool(0x8D64d8273a3D50E44Cc0e6F43d927f78754EdefB);
    BoringVault public LHYPE = BoringVault(payable(0x5748ae796AE46A4F1348a1693de4b50560485562));

    address tokenIn = 0x94e8396e0869c9F2200760aF0621aFd240E1CF38; // wstHYPE
    address tokenOut = 0x5555555555555555555555555555555555555555; // WHYPE
    uint256 interestRateMode = 2; // 1 for stable, 2 for variable

    error LHYPEDeleverage__HealthFactorBelowMinimum(uint256 healthFactor, uint256 minimumEndingHealthFactor);
    error LHYPEDeleverage__SlippageTooHigh(uint256 wstHYPEReceived, uint256 maxWstHypePaid);

    constructor() {
        ERC20(tokenOut).approve(address(hypurrfiPool), type(uint256).max);
    }

    function deleverage(
        uint256 hypeToDeleverage,
        uint256 maxwstHypeWithdrawn,
        uint256 minimumEndingHealthFactor
    )
        external
        returns (uint256 amountWstHypePaid)
    {
        // initiate a flashswap
        amountWstHypePaid = exactOutputInternal(hypeToDeleverage, address(this), 0, "");
        if (amountWstHypePaid > maxwstHypeWithdrawn) {
            revert LHYPEDeleverage__SlippageTooHigh(amountWstHypePaid, maxwstHypeWithdrawn);
        }

        (,,,,, uint256 healthFactor) = hypurrfiPool.getUserAccountData(address(LHYPE));

        if (healthFactor < minimumEndingHealthFactor) {
            revert LHYPEDeleverage__HealthFactorBelowMinimum(healthFactor, minimumEndingHealthFactor);
        }
    }

    /// @inheritdoc IHyperswapV3SwapCallback
    function hyperswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        // get the desired HYPE
        console.log("hyperswapV3SwapCallback");
        console.log("amount0Delta", amount0Delta);
        console.log("amount1Delta", amount1Delta);
        console.log("WHYPE BAL: ", ERC20(tokenOut).balanceOf(address(this)));

        // Repay on behalf of LHYPE
        // hardcoding token0 amount, as tokenIn and out do not change
        hypurrfiPool.repay(tokenOut, uint256(-amount0Delta), interestRateMode, address(LHYPE));

        // Call manage() on LHYPE to make the withdraw of stHYPE to this address
        LHYPE.manage(
            address(hypurrfiPool),
            abi.encodeWithSelector(
                IPool.withdraw.selector,
                0x94e8396e0869c9F2200760aF0621aFd240E1CF38,
                uint256(amount1Delta),
                address(this)
            ),
            0
        );

        // Repay the flashswap using the stHYPE
        ERC20(tokenIn).transfer(address(hyperswapPool), uint256(amount1Delta));
    }

    /// @dev function is taken from UniswapV3 Router, but uses the identical provided _getPool() instead of getPool()
    function exactOutputInternal(
        uint256 amountOut,
        address recipient,
        uint160 sqrtPriceLimitX96,
        bytes memory data
    )
        private
        returns (uint256 amountIn)
    {
        // allow swapping to the router address with address 0
        if (recipient == address(0)) recipient = address(this);

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0Delta, int256 amount1Delta) = hyperswapPool.swap(
            recipient,
            zeroForOne,
            -amountOut.toInt256(),
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            data
        );

        uint256 amountOutReceived;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));

        // it's technically possible to not receive the full output amount,
        // so if no price limit has been specified, require this possibility away
        if (sqrtPriceLimitX96 == 0) require(amountOutReceived == amountOut);
    }
}
