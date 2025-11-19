// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { IFeeModule, IERC20 } from "./interfaces/IFeeModule.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title SimpleFeeModule
 * @notice A simple fee module implementation that charges a percentage fee
 * @dev Fees are sent to a designated fee recipient
 */
contract SimpleFeeModule is IFeeModule {

    uint256 constant ONE_HUNDRED_PERCENT = 10_000;
    uint256 public immutable offerFeePercentage;

    error FeePercentageTooHigh(uint256 feePercentage, uint256 maxAllowed);

    /**
     * @notice Initialize the SimpleFeeModule
     * @param _offerFeePercentage Fee percentage on offer assets in basis points
     */
    constructor(uint256 _offerFeePercentage) {
        if (_offerFeePercentage > ONE_HUNDRED_PERCENT) {
            revert FeePercentageTooHigh(_offerFeePercentage, ONE_HUNDRED_PERCENT);
        }

        offerFeePercentage = _offerFeePercentage;
    }

    function calculateOfferFees(
        uint256 amount,
        IERC20 offerAsset,
        IERC20 wantAsset,
        address receiver
    )
        external
        view
        returns (uint256 newAmountForReceiver, uint256 feeAmount)
    {
        feeAmount = (amount * offerFeePercentage) / ONE_HUNDRED_PERCENT;
        newAmountForReceiver = amount - feeAmount;
    }

}
