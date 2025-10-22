// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { OneToOneQueue } from "../OneToOneQueue.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IFeeModule
 * @notice Interface for modular fee calculation logic
 * @dev Allows different fee implementations to be plugged into the Queue contract
 */
interface IFeeModule {
    struct PostFeeProcessedOrder {
        uint256 finalAmount;
        IERC20 asset;
        address receiver;
    }

    /**
     * @notice Calculate fees for a batch of orders being processed
     * @param orders Array of orders being processed
     * @param orderIDs, array of orderIDs, since they may not always be in order after filtering out pre-fills
     * @return postFeeProcessedOrders object regarding how much of what should be sent where
     * @return feeAssets array of addresses of assets to be taken in fees
     * @return feeAmounts array of amounts of assets to be taken in fees
     */
    function calculateFees(
        OneToOneQueue.Order[] calldata orders,
        uint256[] calldata orderIDs
    )
        external
        view
        returns (
            PostFeeProcessedOrder[] memory postFeeProcessedOrders,
            IERC20[] memory feeAssets,
            uint256[] memory feeAmounts
        );
}
