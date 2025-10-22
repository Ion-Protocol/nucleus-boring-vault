// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IFeeModule, IERC20 } from "./interfaces/IFeeModule.sol";
import { OneToOneQueue } from "./OneToOneQueue.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title SimpleFeeModule
 * @notice A simple fee module implementation that charges a percentage fee
 * @dev Fees are sent to a designated fee recipient
 */
contract SimpleFeeModule is IFeeModule {
    uint256 public immutable feePercentage;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the SimpleFeeModule
     * @param _feePercentage Fee percentage in basis points
     */
    constructor(uint256 _feePercentage) {
        require(_feePercentage <= 10_000, "SimpleFeeModule: fee percentage too high");

        feePercentage = _feePercentage;
    }

    /*//////////////////////////////////////////////////////////////
                          FEE CALCULATION
    //////////////////////////////////////////////////////////////*/
    function calculateFees(
        OneToOneQueue.Order[] calldata orders,
        uint256[] calldata orderIDs
    )
        external
        view
        returns (
            IFeeModule.PostFeeProcessedOrder[] memory postFeeProcessedOrders,
            IERC20[] memory feeAssets,
            uint256[] memory feeAmounts
        )
    {
        uint256 length = orders.length;
        postFeeProcessedOrders = new IFeeModule.PostFeeProcessedOrder[](length);
        feeAssets = new IERC20[](length);
        feeAmounts = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            uint256 fee = orders[i].amount * feePercentage / 10_000;
            uint256 finalAmount = orders[i].amount - fee;

            postFeeProcessedOrders[i] = IFeeModule.PostFeeProcessedOrder({
                finalAmount: finalAmount,
                asset: IERC20(address(orders[i].wantAsset)),
                receiver: IERC721(msg.sender).ownerOf(orderIDs[i]) // Since different queues may use this function,
                    // reference the caller as the ERC721 to lookup token owners
             });

            /// NOTE: taking fees in offer assets... Curious if any opinions here (USDC most of the time)
            feeAssets[i] = IERC20(address(orders[i].offerAsset));
            feeAmounts[i] = fee;
        }
    }
}
