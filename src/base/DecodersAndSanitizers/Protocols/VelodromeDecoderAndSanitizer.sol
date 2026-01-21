// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IVelodromeNonFungiblePositionManager } from "src/interfaces/IVelodromeNonFungiblePositionManager.sol";
import {
    BaseDecoderAndSanitizer,
    DecoderCustomTypes
} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract VelodromeDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== ERRORS ===============================

    error VelodromeDecoderAndSanitizer__ReceiverNotBoringVault();
    error VelodromeDecoderAndSanitizer__BadPathFormat();
    error VelodromeDecoderAndSanitizer__BadTokenId();

    //============================== IMMUTABLES ===============================

    /**
     * @notice The networks velodrome nonfungible position manager.
     */
    IVelodromeNonFungiblePositionManager internal immutable velodromeNonFungiblePositionManager;

    constructor(address _velodromeNonFungiblePositionManager) {
        velodromeNonFungiblePositionManager = IVelodromeNonFungiblePositionManager(_velodromeNonFungiblePositionManager);
    }

    //============================== Velodrome ===============================

    // @tag token0:address
    // @tag token1:address
    // @tag recipient:address
    function mint(DecoderCustomTypes.VelodromeMintParams calldata params)
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        // Nothing to sanitize
        // Return addresses found
        addressesFound = abi.encodePacked(params.token0, params.token1, params.recipient);
    }

    // @desc Specify the operator and tokens that can increase liquidity, boringVault must always be the token ID owner
    // @tag operator:address
    // @tag token0:address
    // @tag token1:address
    function increaseLiquidity(DecoderCustomTypes.IncreaseLiquidityParams calldata params)
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        // Sanitize raw data
        if (velodromeNonFungiblePositionManager.ownerOf(params.tokenId) != boringVault) {
            revert VelodromeDecoderAndSanitizer__BadTokenId();
        }
        // Extract addresses from velodromeNonFungiblePositionManager.positions(params.tokenId).
        (, address operator, address token0, address token1,,,,,,,,) =
            velodromeNonFungiblePositionManager.positions(params.tokenId);
        addressesFound = abi.encodePacked(operator, token0, token1);
    }

    // @desc BoringVault must always be the token ID owner
    function decreaseLiquidity(DecoderCustomTypes.DecreaseLiquidityParams calldata params)
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        // Sanitize raw data
        // NOTE ownerOf check is done in PositionManager contract as well, but it is added here
        // just for completeness.
        if (velodromeNonFungiblePositionManager.ownerOf(params.tokenId) != boringVault) {
            revert VelodromeDecoderAndSanitizer__BadTokenId();
        }

        // No addresses in data
        return addressesFound;
    }

    // @desc BoringVault must always be the token ID owner
    // @tag recipient:address
    function collect(DecoderCustomTypes.CollectParams calldata params)
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        // Sanitize raw data
        // NOTE ownerOf check is done in PositionManager contract as well, but it is added here
        // just for completeness.
        if (velodromeNonFungiblePositionManager.ownerOf(params.tokenId) != boringVault) {
            revert VelodromeDecoderAndSanitizer__BadTokenId();
        }

        // Return addresses found
        addressesFound = abi.encodePacked(params.recipient);
    }

    // @desc Velodrome function to safeTransferFrom ERC721s
    // @tag to:address
    function safeTransferFrom(address, address to, uint256)
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(to);
    }

    // @desc Velodrome function to deposit LP NFT for staking
    function deposit(uint256) external pure virtual returns (bytes memory addressesFound) {
        // Just the NFT ID
        // No addresses in data
        return addressesFound;
    }

    // @desc Velodrome function to withdraw LP NFT from staking
    function withdraw(uint256) external pure virtual returns (bytes memory addressesFound) {
        // Just the NFT ID
        // No addresses in data
        return addressesFound;
    }

    // @desc Velodrome function to CL Gauge for claiming VELO tokens
    function getReward(uint256) external pure virtual returns (bytes memory addressesFound) {
        // Nothing to sanitizer since only the NFT owner can claim rewards.
        return addressesFound;
    }

    // @desc Velodrome function to swap tokens for ETH, only sanitize the first from address and the last to address, we
    // are indifferent to the intermediate route
    // @tag from:address:the from token of the first route
    // @tag to:address:the to token of the last route
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        DecoderCustomTypes.VelodromeV2Route[] calldata routes,
        address to,
        uint256 deadline
    )
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        if (to != address(boringVault)) revert VelodromeDecoderAndSanitizer__ReceiverNotBoringVault();
        addressesFound = abi.encodePacked(routes[0].from, routes[routes.length - 1].to);
    }

    // @desc Velodrome function to swap tokens for ETH, only sanitize the first from address and the last to address, we
    // are indifferent to the intermediate route
    // @tag from:address:the from token of the first route
    // @tag to:address:the to token of the last route
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        DecoderCustomTypes.VelodromeV2Route[] calldata routes,
        address to,
        uint256 deadline
    )
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        if (to != address(boringVault)) revert VelodromeDecoderAndSanitizer__ReceiverNotBoringVault();
        addressesFound = abi.encodePacked(routes[0].from, routes[routes.length - 1].to);
    }

}
