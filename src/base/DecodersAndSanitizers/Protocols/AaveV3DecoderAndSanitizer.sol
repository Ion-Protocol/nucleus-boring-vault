// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract AaveV3DecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== AAVEV3 ===============================

    // @desc Supply to the Aave V3 protocol
    // @tag asset:address:the address of the supply asset
    // @tag onBehalfOf:address:the address to supply on behalf of
    function supply(
        address asset,
        uint256,
        address onBehalfOf,
        uint16
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(asset, onBehalfOf);
    }

    // @desc Withdraw from the Aave V3 protocol
    // @tag asset:address:the address of the withdraw asset
    // @tag to:address:the address to withdraw to
    function withdraw(address asset, uint256, address to) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(asset, to);
    }

    // @desc Borrow from the Aave V3 protocol
    // @tag asset:address:the address of the borrow asset
    // @tag onBehalfOf:address:the address to borrow on behalf of
    function borrow(
        address asset,
        uint256,
        uint256,
        uint16,
        address onBehalfOf
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(asset, onBehalfOf);
    }

    // @desc Repay an Aave V3 loan
    // @tag asset:address:the address of the repay asset
    // @tag onBehalfOf:address:the address to repay on behalf of
    function repay(
        address asset,
        uint256,
        uint256,
        address onBehalfOf
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(asset, onBehalfOf);
    }

    // @desc Required for Aave V3 to enable deposits as collateral
    // @tag asset:address:the address of the collateral asset
    function setUserUseReserveAsCollateral(
        address asset,
        bool useAsCollateral
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(asset);
    }

    // @desc allow higher liquidation threshold for correlated assets
    function setUserEMode(uint8) external pure virtual returns (bytes memory addressesFound) {
        // Nothing to sanitize or return
        return addressesFound;
    }

    // @desc Borrow ETH from the Aave V3 protocol, address is ignored by protocol and WETH is used for internal
    // POOL.borrow
    function borrowETH(address, uint256, uint16) external pure returns (bytes memory addressesFound) {
        // nothing to sanitize or return
        return addressesFound;
    }

}
