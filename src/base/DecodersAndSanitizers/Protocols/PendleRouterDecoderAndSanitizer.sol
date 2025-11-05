// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {
    BaseDecoderAndSanitizer,
    DecoderCustomTypes
} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract PendleRouterDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== ERRORS ===============================

    error PendleRouterDecoderAndSanitizer__AggregatorSwapsNotPermitted();
    error PendleRouterDecoderAndSanitizer__LimitOrderSwapsNotPermitted();

    //============================== PENDLEROUTER ===============================

    // @desc Function to mint Pendle Sy using some token, will revert if using aggregator swaps
    // @tag user:address:The user to mint to
    // @tag sy:address:The sy token to mint
    // @tag input:address:The input token to mint from
    function mintSyFromToken(
        address user,
        address sy,
        uint256,
        DecoderCustomTypes.TokenInput calldata input
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        if (
            input.swapData.swapType != DecoderCustomTypes.SwapType.NONE || input.swapData.extRouter != address(0)
                || input.pendleSwap != address(0) || input.tokenIn != input.tokenMintSy
        ) revert PendleRouterDecoderAndSanitizer__AggregatorSwapsNotPermitted();

        addressesFound = abi.encodePacked(user, sy, input.tokenIn);
    }

    // @desc Function to mint Pendle Py using the Sy
    // @tag user:address:The user to mint to
    // @tag yt:address:The yt token to mint
    function mintPyFromSy(
        address user,
        address yt,
        uint256,
        uint256
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(user, yt);
    }

    // @desc Function to swap exact Pendle Pt for Pendle Yt
    // @tag user:address:The user to swap from
    // @tag market:address:The pendle market address
    function swapExactPtForYt(
        address user,
        address market,
        uint256,
        uint256,
        DecoderCustomTypes.ApproxParams calldata
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(user, market);
    }

    // @desc Function to withdraw from Pendle PT tokens, does not support limit orders or aggregator swaps.
    // @param receiver:address
    // @param market:address
    // @param tokenOut:address
    function swapExactPtForToken(
        address receiver,
        address market,
        uint256 minPtOut,
        DecoderCustomTypes.TokenOutput calldata output,
        DecoderCustomTypes.LimitOrderData calldata limit
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        if (limit.limitRouter != address(0)) {
            revert PendleRouterDecoderAndSanitizer__LimitOrderSwapsNotPermitted();
        }

        if (
            output.swapData.swapType != DecoderCustomTypes.SwapType.NONE || output.swapData.extRouter != address(0)
                || output.pendleSwap != address(0) || output.tokenOut != output.tokenRedeemSy
        ) revert PendleRouterDecoderAndSanitizer__AggregatorSwapsNotPermitted();

        addressesFound = abi.encodePacked(receiver, market, output.tokenOut);
    }

    // @desc Function to swap exact Pendle Yt for Pendle Pt
    // @tag user:address:The user to swap from
    // @tag market:address:The pendle market address
    function swapExactYtForPt(
        address user,
        address market,
        uint256,
        uint256,
        DecoderCustomTypes.ApproxParams calldata
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(user, market);
    }

    // @desc Function to add Pendle liquidity with Sy and Pt
    // @tag user:address:The user to add liquidity from
    // @tag market:address:The pendle market address
    function addLiquidityDualSyAndPt(
        address user,
        address market,
        uint256,
        uint256,
        uint256
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(user, market);
    }

    // @desc Function to remove Pendle liquidity to Sy and Pt
    // @tag user:address:The user to remove liquidity from
    // @tag market:address:The pendle market address
    function removeLiquidityDualSyAndPt(
        address user,
        address market,
        uint256,
        uint256,
        uint256
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(user, market);
    }

    // @desc Function to redeem Pendle Py to Sy
    // @tag user:address:The user to redeem from
    // @tag yt:address:The yt token to redeem
    function redeemPyToSy(
        address user,
        address yt,
        uint256,
        uint256
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(user, yt);
    }

    // @desc Function to redeem Pendle Sy to some token, will revert if using aggregator swaps
    // @tag user:address:The user to redeem from
    // @tag sy:address:The sy token to redeem
    // @tag output:address:The token to redeem to
    function redeemSyToToken(
        address user,
        address sy,
        uint256,
        DecoderCustomTypes.TokenOutput calldata output
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        if (
            output.swapData.swapType != DecoderCustomTypes.SwapType.NONE || output.swapData.extRouter != address(0)
                || output.pendleSwap != address(0) || output.tokenOut != output.tokenRedeemSy
        ) revert PendleRouterDecoderAndSanitizer__AggregatorSwapsNotPermitted();

        addressesFound = abi.encodePacked(user, sy, output.tokenOut);
    }

    // @desc Function to swap exact token for Pendle Pt, will revert if using aggregator swaps or limit orders
    // @tag receiver:address:The receiver of the Pendle Pt
    // @tag market:address:The pendle market address
    // @tag input:address:The token to swap from
    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256 minPtOut,
        DecoderCustomTypes.ApproxParams calldata guessPtOut,
        DecoderCustomTypes.TokenInput calldata input,
        DecoderCustomTypes.LimitOrderData calldata limit
    )
        external
        pure
        virtual
        returns (bytes memory addressFound)
    {
        if (
            input.swapData.swapType != DecoderCustomTypes.SwapType.NONE || input.swapData.extRouter != address(0)
                || input.pendleSwap != address(0) || input.tokenIn != input.tokenMintSy
        ) {
            revert PendleRouterDecoderAndSanitizer__AggregatorSwapsNotPermitted();
        }

        if (limit.limitRouter != address(0)) {
            revert PendleRouterDecoderAndSanitizer__LimitOrderSwapsNotPermitted();
        }

        addressFound = abi.encodePacked(receiver, market, input.tokenIn);
    }

    // @desc function to claim PENDLE token rewards and interest from LPing
    // @tag packedArgs:bytes:packed all sys,yts, and markets in order
    function redeemDueInterestAndRewards(
        address user,
        address[] calldata sys,
        address[] calldata yts,
        address[] calldata markets
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(user);
        uint256 sysLength = sys.length;
        for (uint256 i; i < sysLength; ++i) {
            addressesFound = abi.encodePacked(addressesFound, sys[i]);
        }
        uint256 ytsLength = yts.length;
        for (uint256 i; i < ytsLength; ++i) {
            addressesFound = abi.encodePacked(addressesFound, yts[i]);
        }
        uint256 marketsLength = markets.length;
        for (uint256 i; i < marketsLength; ++i) {
            addressesFound = abi.encodePacked(addressesFound, markets[i]);
        }
    }

    // @desc function to add liquidity with a single token and keep the yt, will revert if using aggregator swaps
    // @tag receiver:address:The receiver of the Pendle Yt and lp
    // @tag market:address:The pendle market address
    // @tag input:address:The token to add liquidity from
    function addLiquiditySingleTokenKeepYt(
        address receiver,
        address market,
        uint256 minLpOut,
        uint256 minYtOut,
        DecoderCustomTypes.TokenInput calldata input
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        if (
            input.swapData.swapType != DecoderCustomTypes.SwapType.NONE || input.swapData.extRouter != address(0)
                || input.pendleSwap != address(0) || input.tokenIn != input.tokenMintSy
        ) {
            revert PendleRouterDecoderAndSanitizer__AggregatorSwapsNotPermitted();
        }

        addressesFound = abi.encodePacked(receiver, market, input.tokenIn);
    }

    // @desc Function to add liquidity with a single token, does not keep the yt, will revert if using aggregator swaps
    // or limit orders
    // @tag receiver:address:The receiver of the Pendle Yt and lp
    // @tag market:address:The pendle market address
    // @tag input:address:The token to add liquidity from
    function addLiquiditySingleToken(
        address receiver,
        address market,
        uint256 minLpOut,
        DecoderCustomTypes.ApproxParams calldata guessPtReceivedFromSy,
        DecoderCustomTypes.TokenInput calldata input,
        DecoderCustomTypes.LimitOrderData calldata limit
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        if (
            input.swapData.swapType != DecoderCustomTypes.SwapType.NONE || input.swapData.extRouter != address(0)
                || input.pendleSwap != address(0) || input.tokenIn != input.tokenMintSy
        ) {
            revert PendleRouterDecoderAndSanitizer__AggregatorSwapsNotPermitted();
        }

        if (limit.limitRouter != address(0)) {
            revert PendleRouterDecoderAndSanitizer__LimitOrderSwapsNotPermitted();
        }

        addressesFound = abi.encodePacked(receiver, market, input.tokenIn);
    }

    // @desc Function to remove liquidity into a single token, will revert if using aggregator swaps or limit orders
    // @tag receiver:address:The receiver of the token to remove liquidity into
    // @tag market:address:The pendle market address
    // @tag output:address:The token to receive after removing liquidity
    function removeLiquiditySingleToken(
        address receiver,
        address market,
        uint256 netLpToRemove,
        DecoderCustomTypes.TokenOutput calldata output,
        DecoderCustomTypes.LimitOrderData calldata limit
    )
        external
        pure
        virtual
        returns (bytes memory addressFound)
    {
        if (
            output.swapData.swapType != DecoderCustomTypes.SwapType.NONE || output.swapData.extRouter != address(0)
                || output.pendleSwap != address(0) || output.tokenOut != output.tokenRedeemSy
        ) {
            revert PendleRouterDecoderAndSanitizer__AggregatorSwapsNotPermitted();
        }

        if (limit.limitRouter != address(0)) {
            revert PendleRouterDecoderAndSanitizer__LimitOrderSwapsNotPermitted();
        }

        addressFound = abi.encodePacked(receiver, market, output.tokenOut);
    }

    function exitPostExpToToken(
        address receiver,
        address market,
        uint256 netPtIn,
        uint256 netLpIn,
        DecoderCustomTypes.TokenOutput calldata output
    )
        external
        pure
        returns (bytes memory addressFound)
    {
        if (
            output.swapData.swapType != DecoderCustomTypes.SwapType.NONE || output.swapData.extRouter != address(0)
                || output.pendleSwap != address(0)
        ) {
            revert PendleRouterDecoderAndSanitizer__AggregatorSwapsNotPermitted();
        }

        addressFound = abi.encodePacked(receiver, market, output.tokenOut, output.tokenRedeemSy);
    }

}
