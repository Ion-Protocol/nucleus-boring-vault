// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { AggregationRouterV6 } from "src/interfaces/AggregationRouterV6.sol";
import { IOKXRouter } from "src/interfaces/IOKXRouter.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CrossChainTellerBase, BridgeData } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { ReentrancyGuard } from "@solmate/utils/ReentrancyGuard.sol";
import { WETH } from "@solmate/tokens/WETH.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";

/**
 * @custom:security-contact security@molecularlabs.io
 */
contract DexAggregatorWrapper is ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    AggregationRouterV6 public immutable aggregator;
    IOKXRouter public immutable okxRouter;
    address public immutable okxApprover;
    WETH public immutable canonicalWrapToken;

    // Function selectors for OKX router functions
    bytes4 private constant SMART_SWAP_BY_ORDER_ID_SELECTOR = 0xb80c2f09;
    bytes4 private constant SMART_SWAP_TO_SELECTOR = 0x03b87e5f;
    bytes4 private constant UNISWAP_V3_SWAP_TO_SELECTOR = 0x0d5f0e3b;
    bytes4 private constant UNISWAP_V3_SWAP_TO_WITH_PERMIT_SELECTOR = 0xf3e144b6;
    bytes4 private constant UNXSWAP_BY_ORDER_ID_SELECTOR = 0x9871efa4;
    bytes4 private constant UNXSWAP_TO_SELECTOR = 0x08298b5a;

    error DexAggregatorWrapper__InvalidSwapDescription();
    error DexAggregatorWrapper__UnsupportedOkxFunction();
    error DexAggregatorWrapper__OkxSwapFailed();
    error DexAggregatorWrapper__InsufficientEthForSwap();
    error DexAggregatorWrapper__EthRefundFailed();

    event Deposit(
        address indexed depositAsset,
        address indexed receiver,
        address indexed supportedAsset,
        uint256 depositAmount,
        uint256 supportedAssetAmount,
        uint256 shareAmount
    );

    /**
     * @notice Initializes the DexAggregatorWrapper with necessary contract addresses
     * @param _aggregator is the AggregationRouterV6 oneInch contract
     * @param _okxRouter The address of the OKX DEX Router contract
     * @param _okxApprover The address of the OKX token approver contract
     * @param _canonicalWrapToken The address of the canonical wrap token
     */
    constructor(
        AggregationRouterV6 _aggregator,
        IOKXRouter _okxRouter,
        address _okxApprover,
        WETH _canonicalWrapToken
    ) {
        aggregator = _aggregator;
        okxRouter = _okxRouter;
        okxApprover = _okxApprover;
        canonicalWrapToken = _canonicalWrapToken;
    }

    /**
     * @notice Allows users to swap tokens via 1inch and deposit the result into a vault
     * @param supportedAsset The asset accepted by the Teller
     * @param recipient The address to receive the share tokens
     * @param teller The Teller contract that will receive the supported asset
     * @param minimumMint The minimum number of shares that must be minted
     * @param executor The address executing the 1inch swap
     * @param desc The 1inch swap description containing trade details
     * @param data Additional data required by the 1inch aggregator
     * @param nativeValueToWrap The amount of native token to wrap for the swap (if any)
     * @return shares The amount of shares minted to the recipient
     */
    function depositOneInch(
        ERC20 supportedAsset,
        address recipient,
        TellerWithMultiAssetSupport teller,
        uint256 minimumMint,
        address executor,
        AggregationRouterV6.SwapDescription calldata desc,
        bytes calldata data,
        uint256 nativeValueToWrap
    )
        external
        payable
        nonReentrant
        returns (uint256 shares)
    {
        uint256 supportedAssetAmount =
            _oneInchHelper(supportedAsset, address(teller), executor, desc, data, nativeValueToWrap);

        // Deposit into the vault
        shares = teller.deposit(supportedAsset, supportedAssetAmount, minimumMint, recipient);

        emit Deposit(
            address(desc.srcToken), recipient, address(supportedAsset), desc.amount, supportedAssetAmount, shares
        );
    }

    /**
     * @notice Swaps tokens via 1inch, deposits the result into a vault, and bridges the shares
     * @param supportedAsset The asset accepted by the Teller
     * @param teller The CrossChainTellerBase contract that will receive the supported asset
     * @param minimumMint The minimum number of shares that must be minted
     * @param bridgeData Data required for the bridge operation
     * @param executor The address executing the 1inch swap
     * @param desc The 1inch swap description containing trade details
     * @param data Additional data required by the 1inch aggregator
     * @param nativeValueToWrap The amount of native token to wrap for the swap (if any)
     */
    function depositAndBridgeOneInch(
        ERC20 supportedAsset,
        CrossChainTellerBase teller,
        uint256 minimumMint,
        BridgeData calldata bridgeData,
        address executor,
        AggregationRouterV6.SwapDescription calldata desc,
        bytes calldata data,
        uint256 nativeValueToWrap
    )
        external
        payable
        nonReentrant
    {
        uint256 supportedAssetAmount =
            _oneInchHelper(supportedAsset, address(teller), executor, desc, data, nativeValueToWrap);

        // Deposit and bridge assets
        (uint256 shares,) = teller.depositAndBridge{ value: msg.value - nativeValueToWrap }(
            supportedAsset, supportedAssetAmount, minimumMint, bridgeData
        );

        _refundExcessEth(payable(msg.sender));

        emit Deposit(
            address(desc.srcToken),
            bridgeData.destinationChainReceiver,
            address(supportedAsset),
            desc.amount,
            supportedAssetAmount,
            shares
        );
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
     * @param nativeValueToWrap The amount of native token to wrap for the swap (if any)
     * @return shares The amount of shares minted
     */
    function depositOkxUniversal(
        ERC20 supportedAsset,
        address recipient,
        TellerWithMultiAssetSupport teller,
        uint256 minimumMint,
        address fromToken,
        uint256 fromTokenAmount,
        bytes calldata okxCallData,
        uint256 nativeValueToWrap
    )
        external
        payable
        nonReentrant
        returns (uint256 shares)
    {
        uint256 supportedAssetAmount =
            _okxHelper(supportedAsset, address(teller), fromToken, fromTokenAmount, okxCallData, nativeValueToWrap);

        // Deposit assets
        shares = teller.deposit(supportedAsset, supportedAssetAmount, minimumMint, recipient);

        emit Deposit(fromToken, recipient, address(supportedAsset), fromTokenAmount, supportedAssetAmount, shares);
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
     * @param nativeValueToWrap The amount of native token to wrap for the swap (if any)
     */
    function depositAndBridgeOkxUniversal(
        ERC20 supportedAsset,
        CrossChainTellerBase teller,
        uint256 minimumMint,
        BridgeData calldata bridgeData,
        address fromToken,
        uint256 fromTokenAmount,
        bytes calldata okxCallData,
        uint256 nativeValueToWrap
    )
        external
        payable
        nonReentrant
    {
        uint256 supportedAssetAmount =
            _okxHelper(supportedAsset, address(teller), fromToken, fromTokenAmount, okxCallData, nativeValueToWrap);

        // Deposit and bridge the assets
        (uint256 shares,) = teller.depositAndBridge{ value: msg.value - nativeValueToWrap }(
            supportedAsset, supportedAssetAmount, minimumMint, bridgeData
        );

        // Refund any excess ETH
        _refundExcessEth(payable(msg.sender));

        emit Deposit(
            fromToken,
            bridgeData.destinationChainReceiver,
            address(supportedAsset),
            fromTokenAmount,
            supportedAssetAmount,
            shares
        );
    }

    /**
     * @notice Helper function to execute 1inch swaps and prepare for deposit
     * @param supportedAsset The asset to be used for deposit after swapping
     * @param teller The address of the teller contract
     * @param executor The address executing the 1inch swap
     * @param desc The 1inch swap description containing trade details
     * @param data Additional data required by the 1inch aggregator
     * @param nativeValueToWrap The amount of native token to wrap for the swap (if any)
     * @return supportedAssetAmount The amount of supported asset received after the swap
     */
    function _oneInchHelper(
        ERC20 supportedAsset,
        address teller,
        address executor,
        AggregationRouterV6.SwapDescription calldata desc,
        bytes calldata data,
        uint256 nativeValueToWrap
    )
        internal
        returns (uint256 supportedAssetAmount)
    {
        bool useNative = _checkAndMintNativeAmount(nativeValueToWrap);
        if (desc.dstToken != supportedAsset || desc.dstReceiver != address(this)) {
            revert DexAggregatorWrapper__InvalidSwapDescription();
        }

        if (useNative) {
            if (desc.srcToken != canonicalWrapToken || desc.amount != nativeValueToWrap) {
                revert DexAggregatorWrapper__InvalidSwapDescription();
            }
            canonicalWrapToken.approve(address(aggregator), nativeValueToWrap);
        } else {
            ERC20 depositAsset = desc.srcToken;
            uint256 depositAmount = desc.amount;

            // Transfer tokens from sender to this contract
            depositAsset.safeTransferFrom(msg.sender, address(this), depositAmount);

            // Perform swap
            depositAsset.safeApprove(address(aggregator), depositAmount);
        }

        (supportedAssetAmount,) = aggregator.swap(executor, desc, data);

        // Approve teller's vault to spend the supported asset
        supportedAsset.safeApprove(address(TellerWithMultiAssetSupport(teller).vault()), supportedAssetAmount);

        return supportedAssetAmount;
    }

    /**
     * @notice Helper function to execute OKX swaps and prepare for deposit
     * @param supportedAsset The asset to be used for deposit after swapping
     * @param teller The address of the teller contract
     * @param fromToken The token to swap from
     * @param fromTokenAmount The amount of tokens to swap
     * @param okxCallData The encoded function call for OKX router
     * @param nativeValueToWrap The amount of native token to wrap for the swap (if any)
     * @return supportedAssetAmount The amount of supported asset received after the swap
     */
    function _okxHelper(
        ERC20 supportedAsset,
        address teller,
        address fromToken,
        uint256 fromTokenAmount,
        bytes calldata okxCallData,
        uint256 nativeValueToWrap
    )
        internal
        returns (uint256 supportedAssetAmount)
    {
        // Check that the function selector is supported
        bytes4 selector;
        assembly {
            selector := calldataload(okxCallData.offset)
        }

        // Check that selector is supported
        // Note: unlike in decoded 1-inch txn, we don't check swap receiver address here
        // but if there is a mismatch, the deposit will fail later on
        if (
            selector == SMART_SWAP_BY_ORDER_ID_SELECTOR || selector == SMART_SWAP_TO_SELECTOR
                || selector == UNISWAP_V3_SWAP_TO_SELECTOR || selector == UNISWAP_V3_SWAP_TO_WITH_PERMIT_SELECTOR
                || selector == UNXSWAP_BY_ORDER_ID_SELECTOR || selector == UNXSWAP_TO_SELECTOR
        ) {
            bool useNative = _checkAndMintNativeAmount(nativeValueToWrap);
            if (useNative) {
                if (fromToken != address(canonicalWrapToken) || fromTokenAmount != nativeValueToWrap) {
                    revert DexAggregatorWrapper__OkxSwapFailed();
                }
                canonicalWrapToken.approve(okxApprover, nativeValueToWrap);
            } else {
                // Transfer tokens from sender to this contract
                ERC20(fromToken).safeTransferFrom(msg.sender, address(this), fromTokenAmount);

                // Approve OKX token approver to spend tokens (not the router directly)
                ERC20(fromToken).safeApprove(okxApprover, fromTokenAmount);
            }

            // Execute the swap with the provided calldata
            (bool success, bytes memory result) = address(okxRouter).call(okxCallData);
            if (!success) {
                // If the call failed, try to extract the revert reason
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }

            // Decode the return value (all functions return uint256)
            supportedAssetAmount = abi.decode(result, (uint256));

            // Approve teller's vault to spend the supported asset
            supportedAsset.safeApprove(address(TellerWithMultiAssetSupport(teller).vault()), supportedAssetAmount);
        } else {
            revert DexAggregatorWrapper__UnsupportedOkxFunction();
        }
    }

    function _checkAndMintNativeAmount(uint256 nativeAmount) internal returns (bool useNative) {
        if (nativeAmount > msg.value) {
            revert DexAggregatorWrapper__InsufficientEthForSwap();
        }
        if (nativeAmount > 0) {
            canonicalWrapToken.deposit{ value: nativeAmount }();
            useNative = true;
        }
    }

    /**
     * @notice Transfers the entire current ETH balance of this contract to the specified recipient.
     * @param _recipient The address to receive the ETH refund.
     * @dev Uses a low-level call and reverts if the transfer fails. This ensures atomicity,
     *      either the whole operation succeeds including refund, or it fails.
     */
    function _refundExcessEth(address payable _recipient) internal {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success,) = _recipient.call{ value: balance }("");
            if (!success) {
                revert DexAggregatorWrapper__EthRefundFailed();
            }
        }
        // If balance is 0, do nothing.
    }
}
