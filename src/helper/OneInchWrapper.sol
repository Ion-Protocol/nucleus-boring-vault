// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { AggregationRouterV6 } from "src/interfaces/AggregationRouterV6.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CrossChainTellerBase, BridgeData } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";

/**
 * @custom:security-contact security@molecularlabs.io
 */
contract OneInchWrapper {
    CrossChainTellerBase public immutable teller;
    ERC20 public immutable supportedAsset;
    AggregationRouterV6 immutable aggregator;

    error OneInchWrapper__InvalidSwapDescription();

    /**
     * @param _supportedAsset is the asset to swap
     * @param _teller is the teller this wrapper supports
     * @param _aggregator is the AggregationRouterV6 oneInch contract
     */
    constructor(ERC20 _supportedAsset, CrossChainTellerBase _teller, AggregationRouterV6 _aggregator) {
        supportedAsset = _supportedAsset;
        teller = _teller;
        aggregator = _aggregator;

        supportedAsset.approve(address(teller.vault()), type(uint256).max);
    }

    /**
     * @notice deposit wrapper, swaps into the supported asset with One Inch
     */
    function deposit(
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

        shares = teller.deposit(supportedAsset, supportedAssetAmount, minimumMint);
        teller.vault().transfer(msg.sender, shares);
    }

    /**
     * @notice depositAndBridge wrapper, swaps into the supported asset with One Inch
     */
    function depositAndBridge(
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

        teller.depositAndBridge{ value: msg.value }(supportedAsset, supportedAssetAmount, minimumMint, bridgeData);
    }
}
