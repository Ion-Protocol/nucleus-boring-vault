// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC721Enumerable, ERC721 } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IFeeModule } from "./interfaces/IFeeModule.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title OneToOneQueue
 * @notice A FIFO queue system for processing withdrawal requests with tokenized receipts
 * @dev Implements ERC721Enumerable for tokenized order receipts
 */
contract OneToOneQueue is ERC721Enumerable, Auth {

    using SafeERC20 for IERC20;

    /// @notice Status of an order in the queue
    enum Status {
        DEFAULT, // Normal order in queue
        PRE_FILLED, // Order filled out of order, skip on solve
        REFUND // Order marked for refund, return offer asset
    }

    /// @notice Approval method for submitting an order
    enum ApprovalMethod {
        EIP20_APROVE,
        EIP2612_PERMIT
    }

    /// @notice Parameters for submitting and approving an order with signatures
    struct SubmissionParams {
        ApprovalMethod approvalMethod;
        uint8 approvalV;
        bytes32 approvalR;
        bytes32 approvalS;
        bool submitWithSignature;
        uint256 deadline;
        bytes eip2612Signature;
        uint256 nonce;
    }

    /// @notice Represents a withdrawal order in the queue
    struct Order {
        uint128 amountOffer; // Amount of offer asset in offer decimals to exchange for the same amount of want asset
            // minus fees.
        uint128 amountWant; // Amount of want asset to give the user in want decimals. This is not inclusive of fees.
        ERC20 offerAsset; // Asset being offered
        ERC20 wantAsset; // Asset being requested
        address refundReceiver; // Address to receive refunds
        Status status; // Current status of the order
    }

    /// @notice Mapping of order index to Order struct
    mapping(uint256 => Order) public queue;

    /// @notice Mapping of hashes that have been used for signatures to prevent replays
    mapping(bytes32 => bool) usedSignatureHashes;

    /// @notice Mapping of supported offer assets
    mapping(address => bool) public supportedOfferAssets;

    /// @notice Mapping of supported want assets
    mapping(address => bool) public supportedWantAssets;

    /// @notice Minimum order size per offer asset
    mapping(address => uint256) public minimumOrderSizePerAsset;

    /// @notice The index of the last order that was processed
    /// @dev Initialized to 0, meaining the queue starts at 1.
    uint256 public lastProcessedOrder;

    /// @notice represents the back of the queue, incremented on sumbiting orders
    uint256 public latestOrder;

    /// @notice Address of the fee module for calculating fees
    IFeeModule public feeModule;

    /// @notice Address of the boring vault
    address public offerAssetRecipient;

    /// @notice recipient of queue fees
    address public feeRecipient;

    event FeeModuleUpdated(IFeeModule indexed oldFeeModule, IFeeModule indexed newFeeModule);
    event OfferAssetAdded(address indexed asset, uint256 minimumOrderSize);
    event OfferAssetRemoved(address indexed asset);
    event WantAssetAdded(address indexed asset);
    event WantAssetRemoved(address indexed asset);
    event MinimumOrderSizeUpdated(address asset, uint256 oldMinimum, uint256 newMinimum);
    event OfferAssetRecipientUpdated(address indexed oldVault, address indexed newVault);
    event OrderSubmitted(
        uint256 indexed orderIndex, Order order, address indexed receiver, bool isSubmittedViaSignature
    );
    event OrdersProcessed(uint256 indexed startIndex, uint256 indexed endIndex);
    event OrderMarkedForRefund(uint256 indexed orderIndex, Order order);
    event OrderForceProcessed(uint256 indexed orderIndex, Order order, address indexed receiver);
    event FeeRecipientUpdated(address indexed oldFeeRecipient, address indexed newFeeRecipient);

    error ZeroAddress();
    error AssetAlreadySupported(address asset);
    error AssetNotSupported(address asset);
    error OrderAlreadyProcessed(uint256 orderIndex);
    error InvalidOrderStatus(uint256 orderIndex, Status currentStatus);
    error InvalidOrderIndex(uint256 orderIndex);
    error AmountBelowMinimum(uint256 amount, uint256 minimum);
    error SignatureExpired(uint256 deadline, uint256 currentTimestamp);
    error SignatureHashAlreadyUsed(bytes32 hash);
    error NotEnoughOrdersToProcess(uint256 ordersToProcess, uint256 latestOrder);
    error InsufficientBalance(
        uint256 orderIndex, address depositor, address asset, uint256 required, uint256 available
    );
    error InsufficientAllowance(
        uint256 orderIndex, address depositor, address asset, uint256 required, uint256 available
    );
    error InvalidOrdersCount(uint256 ordersToProcess);
    error InvalidEip2612Signature(address intendedDepositor, address depositor);
    error InvalidDepositor(address intendedDepositor, address depositor);

    /**
     * @notice Initialize the contract
     * @param _name Name for the ERC721 receipt tokens
     * @param _symbol Symbol for the ERC721 receipt tokens
     * @param _offerAssetRecipient Address of the boring vault
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _offerAssetRecipient,
        address _feeRecipient,
        IFeeModule _feeModule,
        address _owner
    )
        ERC721(_name, _symbol)
        Auth(_owner, Authority(address(0)))
    {
        // no zero check on owner in Auth Contract
        if (_owner == address(0)) revert ZeroAddress();
        if (_offerAssetRecipient == address(0)) revert ZeroAddress();
        if (_feeRecipient == address(0)) revert ZeroAddress();
        if (address(_feeModule) == address(0)) revert ZeroAddress();

        offerAssetRecipient = _offerAssetRecipient;
        feeRecipient = _feeRecipient;
        feeModule = _feeModule;
    }

    /**
     * @notice Set the fee module address
     * @param _feeModule Address of the new fee module
     */
    function setFeeModule(IFeeModule _feeModule) external requiresAuth {
        if (address(_feeModule) == address(0)) revert ZeroAddress();

        IFeeModule oldFeeModule = feeModule;
        feeModule = _feeModule;
        emit FeeModuleUpdated(oldFeeModule, _feeModule);
    }

    /**
     * @notice Set the fee recipient address
     * @param _feeRecipient Address of the new fee module
     */
    function setFeeRecipient(address _feeRecipient) external requiresAuth {
        if (_feeRecipient == address(0)) revert ZeroAddress();

        address oldFeeRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(oldFeeRecipient, _feeRecipient);
    }

    /**
     * @notice Add a supported offer asset
     * @param _asset Address of the offer asset to add
     * @param _minimumOrderSize Minimum order size for this asset
     */
    function addOfferAsset(address _asset, uint256 _minimumOrderSize) external requiresAuth {
        if (_asset == address(0)) revert ZeroAddress();
        if (supportedOfferAssets[_asset]) revert AssetAlreadySupported(_asset);

        supportedOfferAssets[_asset] = true;
        minimumOrderSizePerAsset[_asset] = _minimumOrderSize;

        emit OfferAssetAdded(_asset, _minimumOrderSize);
    }

    /**
     * @notice Update an assets minimum order size
     * @param _asset Address of asset
     * @param _newMinimum for this asset to update to
     */
    function updateAssetMinimumOrderSize(address _asset, uint256 _newMinimum) external requiresAuth {
        if (!supportedOfferAssets[_asset]) revert AssetNotSupported(_asset);

        uint256 oldMinimum = minimumOrderSizePerAsset[_asset];
        minimumOrderSizePerAsset[_asset] = _newMinimum;

        emit MinimumOrderSizeUpdated(_asset, oldMinimum, _newMinimum);
    }

    /**
     * @notice Remove a supported offer asset
     * @param _asset Address of the offer asset to remove
     */
    function removeOfferAsset(address _asset) external requiresAuth {
        if (!supportedOfferAssets[_asset]) revert AssetNotSupported(_asset);

        supportedOfferAssets[_asset] = false;

        emit OfferAssetRemoved(_asset);
    }

    /**
     * @notice Add a supported want asset
     * @param _asset Address of the want asset to add
     */
    function addWantAsset(address _asset) external requiresAuth {
        if (_asset == address(0)) revert ZeroAddress();
        if (supportedWantAssets[_asset]) revert AssetAlreadySupported(_asset);

        supportedWantAssets[_asset] = true;

        emit WantAssetAdded(_asset);
    }

    /**
     * @notice Remove a supported want asset
     * @param _asset Address of the want asset to remove
     */
    function removeWantAsset(address _asset) external requiresAuth {
        if (!supportedWantAssets[_asset]) revert AssetNotSupported(_asset);

        supportedWantAssets[_asset] = false;

        emit WantAssetRemoved(_asset);
    }

    /**
     * @notice Update boring vault address
     * @param _newAddress Address of the new boring vault
     */
    function updateOfferAssetRecipient(address _newAddress) external requiresAuth {
        if (_newAddress == address(0)) revert ZeroAddress();

        address oldVal = offerAssetRecipient;
        offerAssetRecipient = _newAddress;

        emit OfferAssetRecipientUpdated(oldVal, _newAddress);
    }

    /**
     * @notice refund an order and force process it
     * @param orderIndex Index of the order to refund
     */
    function forceRefund(uint256 orderIndex) external requiresAuth {
        if (orderIndex > latestOrder || orderIndex == 0) revert InvalidOrderIndex(orderIndex);
        if (orderIndex <= lastProcessedOrder) revert OrderAlreadyProcessed(orderIndex);

        Order memory order = queue[orderIndex];
        if (order.status != Status.DEFAULT) revert InvalidOrderStatus(orderIndex, order.status);

        queue[orderIndex].status = Status.REFUND;

        _burn(orderIndex);
        IERC20(address(order.offerAsset)).safeTransfer(order.refundReceiver, order.amountOffer);

        emit OrderMarkedForRefund(orderIndex, queue[orderIndex]);
    }

    /**
     * @notice Force process an order out of sequence
     * @param orderIndex Index of the order to force process
     */
    function forceProcess(uint256 orderIndex) external requiresAuth {
        if (orderIndex > latestOrder || orderIndex == 0) revert InvalidOrderIndex(orderIndex);
        if (orderIndex <= lastProcessedOrder) revert OrderAlreadyProcessed(orderIndex);

        Order memory order = queue[orderIndex];

        // require order is set to DEFAULT status
        if (order.status != Status.DEFAULT) revert InvalidOrderStatus(orderIndex, order.status);

        // Mark as pre-filled
        queue[orderIndex].status = Status.PRE_FILLED;

        address receiver = ownerOf(orderIndex);
        _burn(orderIndex);
        IERC20(address(order.wantAsset)).safeTransfer(receiver, order.amountWant);

        emit OrderForceProcessed(orderIndex, order, receiver);
    }

    /**
     * @notice A user facing function to return an order's status in plain english.
     * Possible returns:
     * "complete: pre-filled" order has been pre-filled and is complete
     * "complete: refunded" order has been refunded including the fee and is complete
     * "awaiting processing" order is awaiting processing
     * "complete" order has been processed and is complete
     *
     */
    function getOrderStatus(uint256 orderIndex) external view returns (string memory orderStatusDetails) {
        Order memory order = queue[orderIndex];

        if (order.status == Status.PRE_FILLED) {
            orderStatusDetails = "complete: pre-filled";
            return orderStatusDetails;
        } else if (order.status == Status.REFUND) {
            orderStatusDetails = "complete: refunded";
            return orderStatusDetails;
        }

        if (orderIndex > lastProcessedOrder) {
            orderStatusDetails = string(abi.encodePacked(orderStatusDetails, "awaiting processing"));
        } else {
            orderStatusDetails = string(abi.encodePacked(orderStatusDetails, "complete"));
        }
    }

    function submitOrder(
        uint256 amountOffer,
        ERC20 offerAsset,
        ERC20 wantAsset,
        address intendedDepositor,
        address receiver,
        address refundReceiver,
        SubmissionParams calldata params
    )
        public
        requiresAuth
        returns (uint256 orderIndex)
    {
        {
            if (!supportedOfferAssets[address(offerAsset)]) revert AssetNotSupported(address(offerAsset));
            if (!supportedWantAssets[address(wantAsset)]) revert AssetNotSupported(address(wantAsset));
            uint256 minimumOrderSize = minimumOrderSizePerAsset[address(offerAsset)];
            if (amountOffer < minimumOrderSize) revert AmountBelowMinimum(amountOffer, minimumOrderSize);
            if (receiver == address(0)) revert ZeroAddress();
            if (refundReceiver == address(0)) revert ZeroAddress();
        }

        address depositor;
        if (params.submitWithSignature) {
            if (block.timestamp > params.deadline) revert SignatureExpired(params.deadline, block.timestamp);
            bytes32 hash = keccak256(
                abi.encode(amountOffer, offerAsset, wantAsset, receiver, refundReceiver, params.deadline, params.nonce)
            );
            if (usedSignatureHashes[hash]) revert SignatureHashAlreadyUsed(hash);
            usedSignatureHashes[hash] = true;

            depositor = ECDSA.recover(hash, params.eip2612Signature);
            if (depositor != intendedDepositor) revert InvalidEip2612Signature(intendedDepositor, depositor);
        } else {
            depositor = msg.sender;
            if (depositor != intendedDepositor) revert InvalidDepositor(intendedDepositor, depositor);
        }

        // Do nothing if using standard ERC20 approve
        if (params.approvalMethod == ApprovalMethod.EIP2612_PERMIT) {
            ERC20(address(offerAsset))
                .permit(
                    depositor,
                    address(this),
                    amountOffer,
                    params.deadline,
                    params.approvalV,
                    params.approvalR,
                    params.approvalS
                );
        }

        unchecked {
            orderIndex = ++latestOrder;
        }

        (uint256 newAmountForReceiver, IERC20 feeAsset, uint256 feeAmount) =
            feeModule.calculateOfferFees(amountOffer, offerAsset, wantAsset, receiver);

        _checkBalance(depositor, offerAsset, newAmountForReceiver + feeAmount, orderIndex);
        _checkAllowance(depositor, offerAsset, newAmountForReceiver + feeAmount, orderIndex);

        IERC20(address(offerAsset)).safeTransferFrom(depositor, offerAssetRecipient, newAmountForReceiver);
        feeAsset.safeTransferFrom(depositor, feeRecipient, feeAmount);

        // Create order
        // Since newAmountForReceiver is in offer decimals, we need to calculate the amountWant in want decimals
        Order memory order = Order({
            amountOffer: uint128(amountOffer),
            amountWant: _getWantAmountInWantDecimals(uint128(newAmountForReceiver), offerAsset, wantAsset),
            offerAsset: offerAsset,
            wantAsset: wantAsset,
            refundReceiver: refundReceiver,
            status: Status.DEFAULT
        });
        queue[orderIndex] = order;

        // Mint NFT receipt to receiver
        _safeMint(receiver, orderIndex);

        emit OrderSubmitted(orderIndex, queue[orderIndex], receiver, false);
    }

    /**
     * @notice Process orders sequentially from the queue
     * @param ordersToProcess Number of orders to attempt processing
     * @dev Processes orders starting from lastProcessedOrder + 1
     *      Skips PRE_FILLED orders, processes REFUND orders differently
     *      Requires sufficient want asset balance in contract
     */
    function processOrders(uint256 ordersToProcess) public requiresAuth {
        if (ordersToProcess == 0) revert InvalidOrdersCount(ordersToProcess);

        uint256 startIndex;
        uint256 endIndex;
        unchecked {
            startIndex = lastProcessedOrder + 1;
            endIndex = lastProcessedOrder + ordersToProcess;
        }

        // Ensure we don't go beyond existing orders
        if (endIndex > latestOrder) revert NotEnoughOrdersToProcess(ordersToProcess, latestOrder);

        for (uint256 i; i < ordersToProcess; ++i) {
            uint256 orderIndex = startIndex + i;

            Order memory order = queue[orderIndex];

            if (order.status == Status.PRE_FILLED) {
                // ignore
                continue;
            }

            if (order.status == Status.REFUND) {
                _checkBalance(address(this), order.offerAsset, order.amountOffer, orderIndex);
                IERC20(address(order.offerAsset)).safeTransfer(order.refundReceiver, order.amountOffer);
                _burn(orderIndex);
                continue;
            }

            address receiver = ownerOf(orderIndex);
            _checkBalance(address(this), order.wantAsset, order.amountWant, orderIndex);

            IERC20(address(order.wantAsset)).safeTransfer(receiver, order.amountWant);
            _burn(orderIndex);

            unchecked {
                orderIndex = ++lastProcessedOrder;
            }
        }

        emit OrdersProcessed(startIndex, endIndex);
    }

    /**
     * @notice Submit and immediately process an order if liquidity is available
     * @param amountOffer Amount of offer asset
     * @param offerAsset Asset being offered
     * @param wantAsset Asset being requested
     * @param receiver Address to receive the NFT receipt and want asset
     * @param refundReceiver Address to receive refunds if needed
     * @param params for submission signature use
     * @return orderIndex The index of the created order
     */
    function submitOrderAndProcess(
        uint256 amountOffer,
        ERC20 offerAsset,
        ERC20 wantAsset,
        address intendedDepositor,
        address receiver,
        address refundReceiver,
        SubmissionParams calldata params
    )
        external
        requiresAuth
        returns (uint256 orderIndex)
    {
        orderIndex = submitOrder(
            uint128(amountOffer), offerAsset, wantAsset, intendedDepositor, receiver, refundReceiver, params
        );
        processOrders(orderIndex - lastProcessedOrder);
    }

    function _getWantAmountInWantDecimals(
        uint128 amountOfferAfterFees,
        ERC20 offerAsset,
        ERC20 wantAsset
    )
        internal
        view
        returns (uint128 amountWant)
    {
        uint8 offerDecimals = offerAsset.decimals();
        uint8 wantDecimals = wantAsset.decimals();

        if (offerDecimals == wantDecimals) {
            return amountOfferAfterFees;
        }

        if (offerDecimals > wantDecimals) {
            uint8 difference = offerDecimals - wantDecimals;
            return amountOfferAfterFees / uint128(10 ** difference);
        }

        uint8 difference = wantDecimals - offerDecimals;
        return amountOfferAfterFees * uint128(10 ** difference);
    }

    function _checkBalance(address depositor, ERC20 asset, uint256 amount, uint256 orderIndex) internal view {
        uint256 depositorBalance = asset.balanceOf(depositor);
        if (depositorBalance < amount) {
            revert InsufficientBalance(orderIndex, depositor, address(asset), amount, depositorBalance);
        }
    }

    function _checkAllowance(address depositor, ERC20 asset, uint256 amount, uint256 orderIndex) internal view {
        uint256 depositorAllowance = asset.allowance(depositor, address(this));
        if (depositorAllowance < amount) {
            revert InsufficientAllowance(orderIndex, depositor, address(asset), amount, depositorAllowance);
        }
    }

}
