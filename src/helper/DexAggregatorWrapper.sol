// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { AggregationRouterV6 } from "src/interfaces/AggregationRouterV6.sol";
import { IOKXRouter } from "src/interfaces/IOKXRouter.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CrossChainTellerBase, BridgeData } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";

/**
 * @custom:security-contact security@molecularlabs.io
 */
contract DexAggregatorWrapper {
    AggregationRouterV6 immutable aggregator;
    IOKXRouter immutable okxRouter;
    address immutable okxApprover;

    // Function selectors for OKX router functions
    bytes4 private constant SMART_SWAP_TO_SELECTOR = 0xb80c2f09;
    bytes4 private constant UNXSWAP_TO_SELECTOR = 0xe987197c;
    bytes4 private constant UNISWAP_V3_SWAP_TO_SELECTOR = 0xfe4681d8;
    bytes4 private constant UNISWAP_V3_SWAP_TO_WITH_PERMIT_SELECTOR = 0x64466805;

    error DexAggregatorWrapper__InvalidSwapDescription();
    error DexAggregatorWrapper__InvalidOkxSwapDescription();
    error DexAggregatorWrapper__UnsupportedOkxFunction();
    error DexAggregatorWrapper__OkxSwapFailed();
    error DexAggregatorWrapper__InvalidFromToken();

    /**
     * @param _aggregator is the AggregationRouterV6 oneInch contract
     * @param _okxRouter The address of the OKX DEX Router contract
     * @param _okxApprover The address of the OKX token approver contract
     */
    constructor(AggregationRouterV6 _aggregator, IOKXRouter _okxRouter, address _okxApprover) {
        aggregator = _aggregator;
        okxRouter = _okxRouter;
        okxApprover = _okxApprover;
    }

    /**
     * @notice deposit wrapper, swaps into the supported asset with One Inch
     */
    function depositOneInch(
        ERC20 supportedAsset,
        address recipient,
        TellerWithMultiAssetSupport teller,
        uint256 minimumMint,
        address executor,
        AggregationRouterV6.SwapDescription calldata desc,
        bytes calldata data
    )
        external
        returns (uint256 shares)
    {
        if (desc.dstToken != supportedAsset || desc.dstReceiver != address(this)) {
            revert DexAggregatorWrapper__InvalidSwapDescription();
        }

        ERC20 depositAsset = desc.srcToken;
        uint256 depositAmount = desc.amount;

        depositAsset.transferFrom(msg.sender, address(this), depositAmount);
        // perform swap
        depositAsset.approve(address(aggregator), depositAmount);
        (uint256 supportedAssetAmount,) = aggregator.swap(executor, desc, data);

        supportedAsset.approve(address(teller.vault()), supportedAssetAmount);
        shares = teller.deposit(supportedAsset, supportedAssetAmount, minimumMint, recipient);
    }

    /**
     * @notice depositAndBridge wrapper, swaps into the supported asset with One Inch
     */
    function depositAndBridgeOneInch(
        ERC20 supportedAsset,
        CrossChainTellerBase teller,
        uint256 minimumMint,
        BridgeData calldata bridgeData,
        address executor,
        AggregationRouterV6.SwapDescription calldata desc,
        bytes calldata data
    )
        external
        payable
    {
        if (desc.dstToken != supportedAsset || desc.dstReceiver != address(this)) {
            revert DexAggregatorWrapper__InvalidSwapDescription();
        }
        ERC20 depositAsset = desc.srcToken;
        uint256 depositAmount = desc.amount;

        depositAsset.transferFrom(msg.sender, address(this), depositAmount);
        // perform swap
        depositAsset.approve(address(aggregator), depositAmount);
        (uint256 supportedAssetAmount,) = aggregator.swap(executor, desc, data);

        supportedAsset.approve(address(teller.vault()), supportedAssetAmount);
        teller.depositAndBridge{ value: msg.value }(supportedAsset, supportedAssetAmount, minimumMint, bridgeData);
    }

    /**
     * @notice Universal deposit function that can handle any OKX DEX function
     * @param supportedAsset The asset to deposit after swapping
     * @param recipient The recipient of the shares
     * @param teller The TellerWithMultiAssetSupport contract
     * @param minimumMint The minimum amount of shares to mint
     * @param fromToken The token to swap from
     * @param fromTokenAmount The amount of tokens to swap
     * @param okxCallData The encoded function call for OKX router
     * @return shares The amount of shares minted
     */
    function depositOkxUniversal(
        ERC20 supportedAsset,
        address recipient,
        TellerWithMultiAssetSupport teller,
        uint256 minimumMint,
        address fromToken,
        uint256 fromTokenAmount,
        bytes calldata okxCallData
    )
        external
        payable
        returns (uint256 shares)
    {
        // Check that the function selector is supported
        bytes4 selector;
        assembly {
            selector := calldataload(okxCallData.offset)
        }

        if (
            selector != SMART_SWAP_TO_SELECTOR && selector != UNXSWAP_TO_SELECTOR
                && selector != UNISWAP_V3_SWAP_TO_SELECTOR && selector != UNISWAP_V3_SWAP_TO_WITH_PERMIT_SELECTOR
        ) {
            revert DexAggregatorWrapper__UnsupportedOkxFunction();
        }

        // Transfer tokens from sender to this contract
        ERC20(fromToken).transferFrom(msg.sender, address(this), fromTokenAmount);

        // Approve OKX token approver to spend tokens (not the router directly)
        ERC20(fromToken).approve(okxApprover, fromTokenAmount);

        // Execute the swap with the provided calldata
        (bool success, bytes memory result) = address(okxRouter).call{ value: msg.value }(okxCallData);
        if (!success) {
            // If the call failed, try to extract the revert reason
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        // Decode the return value (all functions return uint256)
        uint256 supportedAssetAmount = abi.decode(result, (uint256));

        // Approve teller's vault to spend the supported asset
        supportedAsset.approve(address(teller.vault()), supportedAssetAmount);

        // Deposit assets
        teller.deposit(supportedAsset, supportedAssetAmount, minimumMint, recipient);
    }

    /**
     * @notice Universal depositAndBridge function that can handle any OKX DEX function
     * @param supportedAsset The asset to deposit after swapping
     * @param teller The CrossChainTellerBase contract
     * @param minimumMint The minimum amount of shares to mint
     * @param bridgeData Data for the bridge operation
     * @param fromToken The token to swap from
     * @param fromTokenAmount The amount of tokens to swap
     * @param okxCallData The encoded function call for OKX router
     */
    function depositAndBridgeOkxUniversal(
        ERC20 supportedAsset,
        CrossChainTellerBase teller,
        uint256 minimumMint,
        BridgeData calldata bridgeData,
        address fromToken,
        uint256 fromTokenAmount,
        bytes calldata okxCallData
    )
        external
        payable
    {
        // Check that the function selector is supported
        bytes4 selector;
        assembly {
            selector := calldataload(okxCallData.offset)
        }

        if (
            selector != SMART_SWAP_TO_SELECTOR && selector != UNXSWAP_TO_SELECTOR
                && selector != UNISWAP_V3_SWAP_TO_SELECTOR && selector != UNISWAP_V3_SWAP_TO_WITH_PERMIT_SELECTOR
        ) {
            revert DexAggregatorWrapper__UnsupportedOkxFunction();
        }

        // Transfer tokens from sender to this contract
        ERC20(fromToken).transferFrom(msg.sender, address(this), fromTokenAmount);

        // Approve OKX token approver to spend tokens (not the router directly)
        ERC20(fromToken).approve(okxApprover, fromTokenAmount);

        // We want to use the majority of our ETH balance for the swap
        // but reserve msg.value for the bridge operation
        uint256 swapValue = address(this).balance - msg.value;

        // Execute the swap with the provided calldata
        (bool success, bytes memory result) = address(okxRouter).call{ value: swapValue }(okxCallData);
        if (!success) {
            // If the call failed, try to extract the revert reason
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        // Decode the return value (all functions return uint256)
        uint256 supportedAssetAmount = abi.decode(result, (uint256));

        // Approve teller's vault to spend the supported asset
        supportedAsset.approve(address(teller.vault()), supportedAssetAmount);

        // Deposit and bridge the assets
        teller.depositAndBridge{ value: msg.value }(supportedAsset, supportedAssetAmount, minimumMint, bridgeData);
    }

    // Function to receive ETH
    receive() external payable { }
}
