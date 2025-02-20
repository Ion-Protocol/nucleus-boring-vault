// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { AggregationRouterV6 } from "src/interfaces/AggregationRouterV6.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CrossChainTellerBase, BridgeData } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";

/**
 * @custom:security-contact security@molecularlabs.io
 */
contract OneInchWrapper {
    AggregationRouterV6 immutable aggregator;

    error OneInchWrapper__InvalidSwapDescription();

    /**
     * @param _aggregator is the AggregationRouterV6 oneInch contract
     */
    constructor(AggregationRouterV6 _aggregator) {
        aggregator = _aggregator;
    }

    /**
     * @notice deposit wrapper, swaps into the supported asset with One Inch
     */
    function deposit(
        ERC20 supportedAsset,
        address recipient,
        CrossChainTellerBase teller,
        uint256 minimumMint,
        address executor,
        AggregationRouterV6.SwapDescription calldata desc,
        bytes calldata data
    )
        external
        returns (uint256 shares)
    {
        if (desc.dstToken != supportedAsset || desc.dstReceiver != address(this)) {
            revert OneInchWrapper__InvalidSwapDescription();
        }

        ERC20 depositAsset = desc.srcToken;
        uint256 depositAmount = desc.amount;

        depositAsset.transferFrom(msg.sender, address(this), depositAmount);
        // perform swap
        depositAsset.approve(address(aggregator), depositAmount);
        (uint256 supportedAssetAmount,) = aggregator.swap(executor, desc, data);

        supportedAsset.approve(address(teller.vault()), supportedAssetAmount);
        shares = teller.deposit(supportedAsset, supportedAssetAmount, minimumMint, recipient);
        teller.vault().transfer(msg.sender, shares);
    }

    /**
     * @notice depositAndBridge wrapper, swaps into the supported asset with One Inch
     */
    function depositAndBridge(
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
            revert OneInchWrapper__InvalidSwapDescription();
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
}
