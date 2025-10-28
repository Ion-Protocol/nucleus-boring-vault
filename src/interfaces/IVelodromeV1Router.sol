// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IVelodromeV1Router {

    function swapExactTokensForTokensSimple(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address to,
        uint256 deadline
    )
        external
        returns (uint256[] memory amounts);

}
