// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract FraxLendDecoderAndSanitizer is BaseDecoderAndSanitizer {
    // @desc borrow from a fraxlend pair
    // @tag token:address:the address of the receiver of the borrow position
    function borrowAsset(uint256, uint256, address receiver) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(receiver);
    }

    // @desc add collateral to a fraxlend pair
    // @tag borrower:address:the address of the borrower
    // @tag token:address:the address of the token to add as collateral
    function addCollateral(
        uint256,
        address borrower,
        address token
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(borrower, token);
    }

    // @desc repay a fraxlend borrow position with collateral, swapper addresses must be approved by contract and are
    // uniV2 swaps
    // @tag borrower:address:the address of the borrower
    function repayAssetWithCollateral(
        address swapperAddress,
        uint256,
        uint256,
        address[] calldata path
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(swapperAddress, path);
    }
}
