// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IUniswapV3SwapCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { SafeCast } from "@uniswap/v3-core/contracts/libraries/SafeCast.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";

library TickMath {
    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;
}

interface IHyperswapV3SwapCallback {
    function hyperswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

contract AaveV3FlashswapDeleverage is Auth, IHyperswapV3SwapCallback {
    using SafeCast for uint256;

    IPool public aaveV3Pool;
    IUniswapV3Pool public uniswapV3Pool;
    BoringVault public boringVault;

    address tokenIn;
    address tokenOut;
    uint256 constant INTEREST_RATE_MODE = 2; // 1 for stable, 2 for variable

    error LHYPEDeleverage__HealthFactorBelowMinimum(uint256 healthFactor, uint256 minimumEndingHealthFactor);
    error LHYPEDeleverage__SlippageTooHigh(uint256 wstHYPEReceived, uint256 maxWstHypePaid);
    error LHYPEDeleverage__InvalidSender();

    constructor(
        address _owner,
        address _aaveV3Pool,
        address _uniswapV3Pool,
        BoringVault _boringVault,
        address _tokenIn, // token that you are withdrawing from the aave v3 pool
        address _tokenOut // token that you are repaying to the aave v3 pool
    )
        Auth(_owner, Authority(address(0)))
    {
        aaveV3Pool = IPool(_aaveV3Pool);
        uniswapV3Pool = IUniswapV3Pool(_uniswapV3Pool);
        boringVault = BoringVault(_boringVault);

        tokenIn = _tokenIn;
        tokenOut = _tokenOut;

        ERC20(tokenOut).approve(address(aaveV3Pool), type(uint256).max);
    }

    function deleverage(
        uint256 hypeToDeleverage,
        uint256 maxWstHypeWithdrawn,
        uint256 minimumEndingHealthFactor
    )
        external
        requiresAuth
        returns (uint256 amountWstHypePaid)
    {
        // initiate a flashswap
        amountWstHypePaid = exactOutputInternal(hypeToDeleverage, address(this), 0, "");

        // Check the slippage on the swap
        if (amountWstHypePaid > maxWstHypeWithdrawn) {
            revert LHYPEDeleverage__SlippageTooHigh(amountWstHypePaid, maxWstHypeWithdrawn);
        }

        // Check the health factor after the deleverage
        (,,,,, uint256 healthFactor) = aaveV3Pool.getUserAccountData(address(boringVault));

        if (healthFactor < minimumEndingHealthFactor) {
            revert LHYPEDeleverage__HealthFactorBelowMinimum(healthFactor, minimumEndingHealthFactor);
        }
    }

    /// @inheritdoc IHyperswapV3SwapCallback
    function hyperswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        if (msg.sender != address(uniswapV3Pool)) {
            revert LHYPEDeleverage__InvalidSender();
        }

        // get the desired HYPE
        // Repay on behalf of boringVault
        // hardcoding token0 amount, as tokenIn and out do not change
        aaveV3Pool.repay(tokenOut, uint256(-amount0Delta), INTEREST_RATE_MODE, address(boringVault));

        // Call manage() on boringVault to make the withdraw of stHYPE to this address
        boringVault.manage(
            address(aaveV3Pool),
            abi.encodeWithSelector(IPool.withdraw.selector, tokenIn, uint256(amount1Delta), address(this)),
            0
        );

        // Repay the flashswap using the stHYPE
        ERC20(tokenIn).transfer(address(uniswapV3Pool), uint256(amount1Delta));
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

        (int256 amount0Delta, int256 amount1Delta) = uniswapV3Pool.swap(
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
