// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

/**
 * @title IOKXRouter Interface
 * @notice Interface for OKX DEX Router contract
 */
interface IOKXRouter {

    struct BaseRequest {
        uint256 fromToken;
        address toToken;
        uint256 fromTokenAmount;
        uint256 minReturnAmount;
        uint256 deadLine;
    }

    struct RouterPath {
        address[] mixAdapters;
        address[] assetTo;
        uint256[] rawData;
        bytes[] extraData;
        uint256 fromToken;
    }

    /**
     * @notice Executes a smart swap directly to a specified receiver address
     * @param orderId Unique identifier for the swap order
     * @param receiver Address to receive the output tokens
     * @param baseRequest Contains parameters like tokens, amounts, deadline
     * @param batchesAmount Array of amounts for each batch in the swap
     * @param batches Detailed routing info for executing swap across different paths
     * @param extraData Additional data for certain swaps
     * @return returnAmount Total amount of destination tokens received
     */
    function smartSwapTo(
        uint256 orderId,
        address receiver,
        BaseRequest calldata baseRequest,
        uint256[] calldata batchesAmount,
        RouterPath[][] calldata batches,
        bytes[] calldata extraData
    )
        external
        payable
        returns (uint256 returnAmount);

    /**
     * @notice Executes a token swap using Unxswap protocol
     * @param srcToken The source token to be swapped
     * @param amount The amount of source token to swap
     * @param minReturnAmount The minimum acceptable return amount
     * @param receiver The address to receive the swapped tokens
     * @param pools Array of pool identifiers for the swap route
     * @return returnAmount The amount of tokens received
     */
    function unxswapTo(
        uint256 srcToken,
        uint256 amount,
        uint256 minReturnAmount,
        address receiver,
        bytes32[] calldata pools
    )
        external
        payable
        returns (uint256 returnAmount);

    /**
     * @notice Executes a token swap using Uniswap V3 protocol
     * @param receiver Encoded recipient address
     * @param amount The amount of source token to swap
     * @param minReturnAmount The minimum acceptable return amount
     * @param pools Array of pool identifiers for the swap route
     * @return returnAmount The amount of tokens received
     */
    function uniswapV3SwapTo(
        uint256 receiver,
        uint256 amount,
        uint256 minReturnAmount,
        uint256[] calldata pools
    )
        external
        payable
        returns (uint256 returnAmount);

    /**
     * @notice Executes a Uniswap V3 swap after obtaining a permit
     * @param receiver Encoded recipient address
     * @param srcToken The token to swap from
     * @param amount The amount of tokens to swap
     * @param minReturnAmount The minimum acceptable return amount
     * @param pools Array of pool identifiers for the swap route
     * @param permit The signed permit message for token approval
     * @return returnAmount The amount of tokens received
     */
    function uniswapV3SwapToWithPermit(
        uint256 receiver,
        ERC20 srcToken,
        uint256 amount,
        uint256 minReturnAmount,
        uint256[] calldata pools,
        bytes calldata permit
    )
        external
        returns (uint256 returnAmount);

}
