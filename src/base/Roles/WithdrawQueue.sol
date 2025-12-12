// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC721Enumerable, ERC721 } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IFeeModule } from "src/interfaces/IFeeModule.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { TellerWithMultiAssetSupport, ERC20 } from "src/base/Roles/TellerWithMultiAssetSupport.sol";

/**
 * @title WithdrawQueue
 * @notice Handles user withdraws using the Teller in a FIFO order
 * @dev Implements ERC721Enumerable for tokenized order receipts
 */
contract WithdrawQueue is ERC721Enumerable, Auth {

    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @notice Type for internal order handling
    /// @dev all but default orders are skipped on solve, as refunds and pre-fills are handled at the time they are
    /// marked
    enum OrderType {
        DEFAULT, // Normal order in queue
        PRE_FILLED, // Order filled out of order, skip on process
        REFUND // Order refunded, skip on process
    }

    /// @notice Return type of a user's order status in the queue
    enum OrderStatus {
        NOT_FOUND,
        PENDING,
        COMPLETE,
        COMPLETE_PRE_FILLED,
        COMPLETE_REFUNDED,
        FAILED_TRANSFER,
        FAILED_REFUND
    }

    /// @notice Approval method for submitting an order
    enum ApprovalMethod {
        EIP20_APROVE,
        EIP2612_PERMIT
    }

    /// @notice Parameters for submitting and approving an order with signatures
    struct SignatureParams {
        ApprovalMethod approvalMethod;
        uint8 approvalV;
        bytes32 approvalR;
        bytes32 approvalS;
        bool submitWithSignature;
        uint256 deadline;
        bytes eip2612Signature;
        uint256 nonce;
    }

    /// @notice Parameters for submitting an order
    struct SubmitOrderParams {
        uint256 amountOffer;
        IERC20 wantAsset;
        address intendedDepositor;
        address receiver;
        address refundReceiver;
        SignatureParams signatureParams;
    }

    /// @notice Represents a withdrawal order in the queue
    struct Order {
        uint256 amountOffer; // Amount of offer asset in offer decimals to exchange for the same amount of want asset
        IERC20 wantAsset; // Asset being requested
        address refundReceiver; // Address to receive refunds
        OrderType orderType; // Current status of the order
        bool didOrderFailTransfer; // Whether the order failed to transfer on process or refund
    }

    /// @notice Mapping of hashes that have been used for signatures to prevent replays
    mapping(bytes32 => bool) public usedSignatureHashes;

    /// @notice Minimum order size per offer asset
    mapping(address => uint256) public minimumOrderSizePerAsset;

    /// @notice Address of the fee module for calculating fees
    IFeeModule public feeModule;

    /// @notice recipient of queue fees
    address public feeRecipient;

    /// @notice Teller this contract is queueing withdraws for
    TellerWithMultiAssetSupport public tellerWithMultiAssetSupport;

    /// @notice the vault of the teller
    IERC20 public immutable offerAsset;

    /// @notice Mapping of order index to Order struct
    mapping(uint256 => Order) public queue;

    /// @notice The index of the last order that was processed
    /// @dev Initialized to 0, meaining the queue starts at 1.
    uint256 public lastProcessedOrder;

    /// @notice represents the back of the queue, incremented on sumbiting orders
    uint256 public latestOrder;

    event FeeModuleUpdated(IFeeModule indexed oldFeeModule, IFeeModule indexed newFeeModule);
    event MinimumOrderSizeUpdated(address indexed asset, uint256 oldMinimum, uint256 newMinimum);
    event FeeRecipientUpdated(address indexed oldFeeRecipient, address indexed newFeeRecipient);
    event OrderSubmitted(
        uint256 indexed orderIndex,
        Order order,
        address indexed receiver,
        address indexed depositor,
        bool isSubmittedViaSignature
    );
    event OrdersProcessedInRange(uint256 indexed startIndex, uint256 indexed endIndex);
    event OrderProcessed(
        uint256 indexed orderIndex, Order order, address indexed receiver, bool indexed isForceProcessed
    );
    event OrderRefunded(uint256 indexed orderIndex, Order order);
    event TellerUpdated(TellerWithMultiAssetSupport indexed oldTeller, TellerWithMultiAssetSupport indexed newTeller);
    event OrderMarkedForRefundByUser(uint256 indexed orderIndex);
    event OrderMarkedForRefundByProtocol(uint256 indexed orderIndex);

    error ZeroAddress();
    error OrderAlreadyProcessed(uint256 orderIndex);
    error InvalidOrderType(uint256 orderIndex, OrderType currentStatus);
    error InvalidOrderIndex(uint256 orderIndex);
    error AmountBelowMinimum(uint256 amount, uint256 minimum);
    error SignatureExpired(uint256 deadline, uint256 currentTimestamp);
    error SignatureHashAlreadyUsed(bytes32 hash);
    error NotEnoughOrdersToProcess(uint256 ordersToProcess, uint256 latestOrder);
    error InsufficientBalanceInQueue(uint256 orderIndex, address asset, uint256 required, uint256 available);
    error InvalidOrdersCount(uint256 ordersToProcess);
    error InvalidEip2612Signature(address intendedDepositor, address depositor);
    error InvalidDepositor(address intendedDepositor, address depositor);
    error PermitFailedAndAllowanceTooLow();
    error TellerVaultMissmatch();
    error MustOwnOrder();
    error QueueMustBeEmpty();
    error AssetNotSupported();

    /**
     * @notice Initialize the contract
     * @param _name Name for the ERC721 receipt tokens
     * @param _symbol Symbol for the ERC721 receipt tokens
     * @param _feeRecipient Address of the fee recipient
     * @param _tellerWithMultiAssetSupport Teller this queue handles withdraws for
     * @param _feeModule Address of fee module contract
     * @param _owner Address of the initial owner
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _feeRecipient,
        TellerWithMultiAssetSupport _tellerWithMultiAssetSupport,
        IFeeModule _feeModule,
        address _owner
    )
        ERC721(_name, _symbol)
        Auth(_owner, Authority(address(0)))
    {
        // no zero check on owner in Auth Contract
        if (_owner == address(0)) revert ZeroAddress();
        if (_feeRecipient == address(0)) revert ZeroAddress();
        if (address(_tellerWithMultiAssetSupport) == address(0)) revert ZeroAddress();
        IERC20 _offerAsset = IERC20(address(_tellerWithMultiAssetSupport.vault()));
        if (address(_offerAsset) == address(0)) revert ZeroAddress();
        if (address(_feeModule) == address(0)) revert ZeroAddress();

        feeRecipient = _feeRecipient;
        tellerWithMultiAssetSupport = _tellerWithMultiAssetSupport;
        offerAsset = _offerAsset;
        feeModule = _feeModule;
    }

    /**
     * @notice Set the fee module address
     * @param _feeModule Address of the new fee module
     */
    function setFeeModule(IFeeModule _feeModule) external requiresAuth {
        if (address(_feeModule) == address(0)) revert ZeroAddress();
        if (totalSupply() != 0) revert QueueMustBeEmpty();

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

    function setTellerWithMultiAssetSupport(TellerWithMultiAssetSupport _newTeller) external requiresAuth {
        if (address(_newTeller) == address(0)) revert ZeroAddress();
        if (address(_newTeller.vault()) != address(offerAsset)) revert TellerVaultMissmatch();
        TellerWithMultiAssetSupport oldTeller = tellerWithMultiAssetSupport;
        tellerWithMultiAssetSupport = _newTeller;
        emit TellerUpdated(oldTeller, _newTeller);
    }

    /**
     * @notice Update an assets minimum order size
     * @param _asset Address of asset
     * @param _newMinimum for this asset to update to
     */
    function updateAssetMinimumOrderSize(address _asset, uint256 _newMinimum) external requiresAuth {
        uint256 oldMinimum = minimumOrderSizePerAsset[_asset];
        minimumOrderSizePerAsset[_asset] = _newMinimum;

        emit MinimumOrderSizeUpdated(_asset, oldMinimum, _newMinimum);
    }

    /**
     * @dev Allows owner to manage ERC20 tokens in the contract to prevent stuck funds
     */
    function manageERC20(IERC20 token, uint256 amount, address receiver) external requiresAuth {
        if (address(token) == address(0)) revert ZeroAddress();
        if (receiver == address(0)) revert ZeroAddress();

        token.safeTransfer(receiver, amount);
    }

    /**
     * @notice Force process multiple orders
     * @param orderIndices Array of order indices to process
     */
    function forceProcessOrders(uint256[] calldata orderIndices) external requiresAuth {
        uint256 length = orderIndices.length;
        for (uint256 i; i < length; ++i) {
            _forceProcess(orderIndices[i]);
        }
    }

    /**
     * @notice Force process an order out of sequence
     * @param orderIndex Index of the order to force process
     */
    function forceProcess(uint256 orderIndex) external requiresAuth {
        _forceProcess(orderIndex);
    }

    /**
     * @notice Cancel an order. Upon process shares will be returned rather than withdrawn
     * @param orderIndex Index of the order to cancel
     */
    function cancelOrder(uint256 orderIndex) external requiresAuth {
        if (ownerOf(orderIndex) != msg.sender) revert MustOwnOrder();
        Order memory order = queue[orderIndex];
        if (order.orderType != OrderType.DEFAULT) revert InvalidOrderType(orderIndex, order.orderType);
        order.orderType = OrderType.REFUND;
        emit OrderMarkedForRefundByUser(orderIndex);
    }

    /**
     * @notice The same as cancelling an order but may be done to any order, not just one owned by the sender. Meant to
     * be a permissioned function
     * @param orderIndex Index of the order to cancel
     */
    function refundOrder(uint256 orderIndex) external requiresAuth {
        Order memory order = queue[orderIndex];
        if (order.orderType != OrderType.DEFAULT) revert InvalidOrderType(orderIndex, order.orderType);
        order.orderType = OrderType.REFUND;
        emit OrderMarkedForRefundByProtocol(orderIndex);
    }

    /**
     * @notice Submit and immediately process a number of orders if liquidity is available
     * @param params SubmitOrderParams struct containing all order parameters
     * @param ordersToProcess Number of orders to process
     * @return orderIndex The index of the created order
     */
    function submitOrderAndProcess(
        SubmitOrderParams calldata params,
        uint256 ordersToProcess
    )
        external
        requiresAuth
        returns (uint256 orderIndex)
    {
        orderIndex = submitOrder(params);
        processOrders(ordersToProcess);
    }

    /**
     * @notice Submit and immediately process an order if liquidity is available. Must process all the preceding orders
     * to do so.
     * @param params SubmitOrderParams struct containing all order parameters
     * @return orderIndex The index of the created order
     */
    function submitOrderAndProcessAll(SubmitOrderParams calldata params)
        external
        requiresAuth
        returns (uint256 orderIndex)
    {
        orderIndex = submitOrder(params);
        // This is = getPendingOrderCount(). OrderIndex = latestOrder but does not require a cold storage read
        processOrders(orderIndex - lastProcessedOrder);
    }

    /**
     * @notice A user facing function to return an order's status
     */
    function getOrderStatus(uint256 orderIndex) external view returns (OrderStatus) {
        if (orderIndex == 0) return OrderStatus.NOT_FOUND;
        Order memory order = queue[orderIndex];

        if (order.orderType == OrderType.PRE_FILLED) {
            return OrderStatus.COMPLETE_PRE_FILLED;
        }

        if (order.orderType == OrderType.REFUND) {
            if (order.didOrderFailTransfer) {
                return OrderStatus.FAILED_REFUND;
            }
            return OrderStatus.COMPLETE_REFUNDED;
        }

        if (order.didOrderFailTransfer) {
            return OrderStatus.FAILED_TRANSFER;
        }

        if (orderIndex > lastProcessedOrder) {
            if (orderIndex > latestOrder) {
                return OrderStatus.NOT_FOUND;
            } else {
                return OrderStatus.PENDING;
            }
        } else {
            return OrderStatus.COMPLETE;
        }
    }

    /**
     * @notice Submit an order at the back of the queue
     * @param params SubmitOrderParams struct containing all order parameters
     */
    function submitOrder(SubmitOrderParams calldata params) public requiresAuth returns (uint256 orderIndex) {
        {
            // TODO: Decide if we want minimums
            // uint256 minimumOrderSize = minimumOrderSizePerAsset[address(params.offerAsset)];
            // if (params.amountOffer < minimumOrderSize) revert AmountBelowMinimum(params.amountOffer,
            // minimumOrderSize);
            if (params.receiver == address(0)) revert ZeroAddress();
            if (params.refundReceiver == address(0)) revert ZeroAddress();
            if (tellerWithMultiAssetSupport.isSupported(ERC20(address(params.wantAsset)))) revert AssetNotSupported();
        }

        address depositor = _verifyDepositor(params);

        // Increment the latestOrder as this one is being minted
        unchecked {
            orderIndex = ++latestOrder;
        }

        // Create order
        // Since newAmountForReceiver is in offer decimals, we need to calculate the amountWant in want decimals
        Order memory order = Order({
            amountOffer: params.amountOffer,
            wantAsset: params.wantAsset,
            refundReceiver: params.refundReceiver,
            orderType: OrderType.DEFAULT,
            didOrderFailTransfer: false
        });
        queue[orderIndex] = order;

        // Transfer the offer assets to the queue to hold until process
        offerAsset.safeTransferFrom(depositor, address(this), params.amountOffer);

        // Mint NFT receipt to receiver
        _safeMint(params.receiver, orderIndex);

        emit OrderSubmitted(
            orderIndex, queue[orderIndex], params.receiver, depositor, params.signatureParams.submitWithSignature
        );
    }

    /**
     * @notice Process orders sequentially from the queue
     * @param ordersToProcess Number of orders to attempt processing
     * @dev Processes orders starting from lastProcessedOrder + 1
     *      Skips PRE_FILLED orders and REFUND orders
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

        // Essentially performing WHILE(++lastProcessedOrder < endIndex)
        // However, using local variables to avoid unnecessary storage reads
        for (uint256 i; i < ordersToProcess; ++i) {
            uint256 orderIndex = startIndex + i;

            Order memory order = queue[orderIndex];

            if (order.orderType != OrderType.DEFAULT) {
                if (order.orderType == OrderType.REFUND) {
                    offerAsset.safeTransfer(order.refundReceiver, order.amountOffer);
                }
                unchecked {
                    ++lastProcessedOrder;
                }
                // ignore
                continue;
            }

            // receiver is the owner of the receipt token
            address receiver = ownerOf(orderIndex);

            // Burn the order after noting the receiver, but before the transfer.
            _burn(orderIndex);

            try tellerWithMultiAssetSupport.bulkWithdraw(
                ERC20(address(order.wantAsset)), order.amountOffer, order.amountOffer, receiver
            ) { }
            catch {
                offerAsset.safeTransfer(order.refundReceiver, order.amountOffer);
            }

            unchecked {
                ++lastProcessedOrder;
            }

            emit OrderProcessed(orderIndex, order, receiver, false);
        }

        emit OrdersProcessedInRange(startIndex, endIndex);
    }

    /**
     * @dev helper function to handle the signature verification and permit for submitting an order
     */
    function _verifyDepositor(SubmitOrderParams calldata params) internal returns (address depositor) {
        if (params.signatureParams.submitWithSignature) {
            if (block.timestamp > params.signatureParams.deadline) {
                revert SignatureExpired(params.signatureParams.deadline, block.timestamp);
            }
            bytes32 hash = keccak256(
                abi.encode(
                    params.amountOffer,
                    offerAsset,
                    params.wantAsset,
                    params.receiver,
                    params.refundReceiver,
                    params.signatureParams.deadline,
                    params.signatureParams.approvalMethod,
                    params.signatureParams.nonce,
                    address(feeModule),
                    block.chainid,
                    address(this)
                )
            );
            if (usedSignatureHashes[hash]) revert SignatureHashAlreadyUsed(hash);
            usedSignatureHashes[hash] = true;

            depositor = ECDSA.recover(hash, params.signatureParams.eip2612Signature);
            // Here we check the intended depositor for a better revert message. If we didn't do this, an incorrect
            // signature would error on the attempt to transfer assets from a nonsense depositor. This error is more
            // descriptive
            if (depositor != params.intendedDepositor) {
                revert InvalidEip2612Signature(params.intendedDepositor, depositor);
            }
        } else {
            depositor = msg.sender;
            if (depositor != params.intendedDepositor) revert InvalidDepositor(params.intendedDepositor, depositor);
        }

        // Do nothing if using standard ERC20 approve
        if (params.signatureParams.approvalMethod == ApprovalMethod.EIP2612_PERMIT) {
            try IERC20Permit(address(offerAsset))
                .permit(
                    depositor,
                    address(this),
                    params.amountOffer,
                    params.signatureParams.deadline,
                    params.signatureParams.approvalV,
                    params.signatureParams.approvalR,
                    params.signatureParams.approvalS
                ) { }
            catch {
                if (offerAsset.allowance(depositor, address(this)) < params.amountOffer) {
                    revert PermitFailedAndAllowanceTooLow();
                }
            }
        }
    }

    /// @notice force process an order in the queue even if it's not at the front
    function _forceProcess(uint256 orderIndex) internal {
        Order memory order = _getOrderEnsureDefault(orderIndex);

        // Mark as pre-filled
        queue[orderIndex].orderType = OrderType.PRE_FILLED;

        address receiver = ownerOf(orderIndex);
        _burn(orderIndex);
        tellerWithMultiAssetSupport.bulkWithdraw(
            ERC20(address(order.wantAsset)), order.amountOffer, order.amountOffer, receiver
        );

        emit OrderProcessed(orderIndex, queue[orderIndex], receiver, true);
    }

    /// @return order after checking index is a real order and is DEFAULT status
    function _getOrderEnsureDefault(uint256 orderIndex) internal returns (Order memory order) {
        // The orderIndex != 0 check is redundant and checked below but more accurate description in the error
        // InvalidOrderIndex
        if (orderIndex > latestOrder || orderIndex == 0) revert InvalidOrderIndex(orderIndex);
        if (orderIndex <= lastProcessedOrder) revert OrderAlreadyProcessed(orderIndex);

        order = queue[orderIndex];

        // require order is set to DEFAULT type
        if (order.orderType != OrderType.DEFAULT) revert InvalidOrderType(orderIndex, order.orderType);
    }

}
