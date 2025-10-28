// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { INonFungiblePositionManager } from "src/interfaces/RawDataDecoderAndSanitizerInterfaces.sol";
import {
    BaseDecoderAndSanitizer,
    DecoderCustomTypes
} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract UniswapV3DecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== ERRORS ===============================

    error UniswapV3DecoderAndSanitizer__BadPathFormat();
    error UniswapV3DecoderAndSanitizer__BadTokenId();

    //============================== IMMUTABLES ===============================

    /**
     * @notice The networks uniswapV3 nonfungible position manager.
     */
    INonFungiblePositionManager internal immutable uniswapV3NonFungiblePositionManager;

    constructor(address _uniswapV3NonFungiblePositionManager) {
        uniswapV3NonFungiblePositionManager = INonFungiblePositionManager(_uniswapV3NonFungiblePositionManager);
    }

    //============================== UNISWAP V3 ===============================

    // @desc Uniswap V3 function to swap by exactInput, will revert if the path is not valid
    // @tag packedArgs:bytes:The path ADDRESSES ONLY of the swap followed by the recipient
    function exactInput(DecoderCustomTypes.ExactInputParams calldata params)
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        // Nothing to sanitize
        // Return addresses found
        // Determine how many addresses are in params.path.
        uint256 chunkSize = 23; // 3 bytes for uint24 fee, and 20 bytes for address token
        uint256 pathLength = params.path.length;
        if (pathLength % chunkSize != 20) revert UniswapV3DecoderAndSanitizer__BadPathFormat();
        uint256 pathAddressLength = 1 + (pathLength / chunkSize);
        uint256 pathIndex;
        for (uint256 i; i < pathAddressLength; ++i) {
            addressesFound = abi.encodePacked(addressesFound, params.path[pathIndex:pathIndex + 20]);
            pathIndex += chunkSize;
        }
        addressesFound = abi.encodePacked(addressesFound, params.recipient);
    }

    // @desc Uniswap V3 function to mint LP
    // @tag token0:address:The first token in the pair
    // @tag token1:address:The second token in the pair
    // @tag recipient:address:The recipient of the LP token
    function mint(DecoderCustomTypes.MintParams calldata params)
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        // Nothing to sanitize
        // Return addresses found
        addressesFound = abi.encodePacked(params.token0, params.token1, params.recipient);
    }

    // @desc Uniswap V3 function to increase liquidity, will revert if the tokenId is not owned by the boring vault
    // @tag operator:address:The operator/owner of the liquidity
    // @tag token0:address:The first token in the pair
    // @tag token1:address:The second token in the pair
    function increaseLiquidity(DecoderCustomTypes.IncreaseLiquidityParams calldata params)
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        // Sanitize raw data
        if (uniswapV3NonFungiblePositionManager.ownerOf(params.tokenId) != boringVault) {
            revert UniswapV3DecoderAndSanitizer__BadTokenId();
        }
        // Extract addresses from uniswapV3NonFungiblePositionManager.positions(params.tokenId).
        (, address operator, address token0, address token1,,,,,,,,) =
            uniswapV3NonFungiblePositionManager.positions(params.tokenId);
        addressesFound = abi.encodePacked(operator, token0, token1);
    }

    // @desc Uniswap V3 function to decrease liquidity, will revert if the tokenId is not owned by the boring vault
    function decreaseLiquidity(DecoderCustomTypes.DecreaseLiquidityParams calldata params)
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        // Sanitize raw data
        // NOTE ownerOf check is done in PositionManager contract as well, but it is added here
        // just for completeness.
        if (uniswapV3NonFungiblePositionManager.ownerOf(params.tokenId) != boringVault) {
            revert UniswapV3DecoderAndSanitizer__BadTokenId();
        }

        // No addresses in data
        return addressesFound;
    }

    // @desc Uniswap V3 function to collect fees, will revert if the tokenId is not owned by the boring vault
    // @tag recipient:address:The recipient of the fees
    function collect(DecoderCustomTypes.CollectParams calldata params)
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        // Sanitize raw data
        // NOTE ownerOf check is done in PositionManager contract as well, but it is added here
        // just for completeness.
        if (uniswapV3NonFungiblePositionManager.ownerOf(params.tokenId) != boringVault) {
            revert UniswapV3DecoderAndSanitizer__BadTokenId();
        }

        // Return addresses found
        addressesFound = abi.encodePacked(params.recipient);
    }

    // @desc Uniswap V3 function to burn empty LP NFTs, will revert if the tokenId is not owned by the boring vault
    function burn(uint256 tokenId) external view virtual returns (bytes memory addressesFound) {
        // Sanitize raw data
        // NOTE ownerOf check is done in PositionManager contract as well, but it is added here
        // just for completeness.
        if (uniswapV3NonFungiblePositionManager.ownerOf(tokenId) != boringVault) {
            revert UniswapV3DecoderAndSanitizer__BadTokenId();
        }
    }

    // @desc Uniswap V3 function to safeTransferFrom ERC721s
    // @tag to:address:The recipient of the ERC721
    function safeTransferFrom(address, address to, uint256)
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(to);
    }

}
