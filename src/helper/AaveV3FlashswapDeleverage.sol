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

interface IGetRate {
    function balancePerShare() external view returns (uint256);
}

contract LHYPEFlashswapDeleverage is Auth, IHyperswapV3SwapCallback {
    using SafeCast for uint256;

    IPool public aaveV3Pool;
    IUniswapV3Pool public uniswapV3Pool;
    BoringVault public boringVault;

    address public constant tokenIn = 0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1; // stHYPE
    address public constant tokenOut = 0x5555555555555555555555555555555555555555; // WHYPE
    address public constant wstHYPE = 0x94e8396e0869c9F2200760aF0621aFd240E1CF38;

    uint256 constant INTEREST_RATE_MODE = 2; // 1 for stable, 2 for variable
    uint256 constant SANITY_CHECK_HEALTH_FACTOR = 1_050_000_000_000_000_000;

    error LHYPEFlashswapDeleverage__HealthFactorBelowMinimum(uint256 healthFactor, uint256 minimumEndingHealthFactor);
    error LHYPEFlashswapDeleverage__SlippageTooHigh(uint256 stHypePaid, uint256 maxStHypePaid);
    error LHYPEFlashswapDeleverage__InvalidSender();
    error LHYPEFlashswapDeleverage__HealthFactorMinimumInvalid(uint256 minimumEndingHealthFactor);

    constructor(
        address _aaveV3Pool,
        address _uniswapV3Pool,
        BoringVault _boringVault
    )
        Auth(address(_boringVault), Authority(address(0)))
    {
        aaveV3Pool = IPool(_aaveV3Pool);
        uniswapV3Pool = IUniswapV3Pool(_uniswapV3Pool);
        boringVault = BoringVault(_boringVault);

        ERC20(tokenOut).approve(address(aaveV3Pool), type(uint256).max);
    }

    function deleverage(
        uint256 hypeToDeleverage,
        uint256 maxStHypePaid,
        uint256 minimumEndingHealthFactor
    )
        external
        requiresAuth
        returns (uint256 amountStHypePaid)
    {
        if (minimumEndingHealthFactor < SANITY_CHECK_HEALTH_FACTOR) {
            revert LHYPEFlashswapDeleverage__HealthFactorMinimumInvalid(minimumEndingHealthFactor);
        }

        // initiate a flashswap
        amountStHypePaid = exactOutputInternal(hypeToDeleverage, address(this), "");

        // Check the slippage on the swap
        if (amountStHypePaid > maxStHypePaid) {
            revert LHYPEFlashswapDeleverage__SlippageTooHigh(amountStHypePaid, maxStHypePaid);
        }

        // Check the health factor after the deleverage
        (,,,,, uint256 healthFactor) = aaveV3Pool.getUserAccountData(address(boringVault));

        if (healthFactor < minimumEndingHealthFactor) {
            revert LHYPEFlashswapDeleverage__HealthFactorBelowMinimum(healthFactor, minimumEndingHealthFactor);
        }
    }

    /// @inheritdoc IHyperswapV3SwapCallback
    function hyperswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        if (msg.sender != address(uniswapV3Pool)) {
            revert LHYPEFlashswapDeleverage__InvalidSender();
        }

        // get the desired HYPE
        // Repay on behalf of boringVault
        // hardcoding token0 amount, as tokenIn and out do not change
        aaveV3Pool.repay(tokenOut, uint256(-amount0Delta), INTEREST_RATE_MODE, address(boringVault));

        // Calculate the amount of wstHYPE to withdraw, as in this case wstHYPE MUST be the withdraw asset but we repay
        // in stHYPE
        uint256 balancePerShare = IGetRate(tokenIn).balancePerShare();
        uint256 wstHypeToWithdraw = uint256(amount1Delta) * 1e18 % balancePerShare == 0
            ? (uint256(amount1Delta) * 1e18 / balancePerShare)
            : ((uint256(amount1Delta) * 1e18 / balancePerShare) + 1);

        // Call manage() on boringVault to make the withdraw of wstHYPE to this address
        boringVault.manage(
            address(aaveV3Pool),
            abi.encodeWithSelector(IPool.withdraw.selector, wstHYPE, wstHypeToWithdraw, address(this)),
            0
        );

        // Repay the flashswap using the stHYPE
        ERC20(tokenIn).transfer(address(uniswapV3Pool), uint256(amount1Delta));
    }

    /// @notice Drain any tokens stuck in the contract
    function drain(ERC20 token, address to, uint256 amount) external requiresAuth {
        token.transfer(to, amount);
    }

    /// @dev function is taken from UniswapV3 Router, but uses the identical provided _getPool() instead of getPool()
    function exactOutputInternal(
        uint256 amountOut,
        address recipient,
        bytes memory data
    )
        private
        returns (uint256 amountIn)
    {
        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0Delta, int256 amount1Delta) = uniswapV3Pool.swap(
            recipient,
            zeroForOne,
            -amountOut.toInt256(),
            (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
            data
        );

        uint256 amountOutReceived;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));

        // it's technically possible to not receive the full output amount,
        // so as no price limit has been specified, require this possibility away
        require(amountOutReceived == amountOut);
    }
}
