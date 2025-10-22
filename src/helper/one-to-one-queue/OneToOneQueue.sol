// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC721Enumerable, ERC721 } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IFeeModule } from "./interfaces/IFeeModule.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console } from "@forge-std/Test.sol";

/**
 * @title OneToOneQueue
 * @notice A FIFO queue system for processing withdrawal requests with tokenized receipts
 * @dev Implements ERC721Enumerable for tokenized order receipts
 */
contract OneToOneQueue is ERC721Enumerable, Auth {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Status of an order in the queue
    enum Status {
        DEFAULT, // Normal order in queue
        PRE_FILLED, // Order filled out of order, skip on solve
        REFUND // Order marked for refund, return offer asset

    }

    /// @notice Represents a withdrawal order in the queue
    struct Order {
        uint256 amount; // Amount of offer asset to exchange for the same amount of the want asset. NOTE: Decimals may
            // differ among these assets, and on processing we convert the offer decimals to want decimals
        ERC20 offerAsset; // Asset being offered
        ERC20 wantAsset; // Asset being requested
        address refundReceiver; // Address to receive refunds
        Status status; // Current status of the order
    }

    enum ApprovalMethod {
        EIP20_APROVE,
        EIP2612_PERMIT
    }

    struct SubmissionParams {
        ApprovalMethod approvalMethod;
        uint8 approvalV;
        bytes32 approvalR;
        bytes32 approvalS;
        bool submitWithSignature;
        uint256 deadline;
        bytes eip2612Signature;
        bytes submissionSignature;
        uint256 nonce;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    // Configuration Events
    /// @notice Emitted when a new fee module is set
    /// @param oldFeeModule Previous fee module address
    /// @param newFeeModule New fee module address
    event FeeModuleUpdated(address indexed oldFeeModule, address indexed newFeeModule);

    /// @notice Emitted when a new offer asset is added
    /// @param asset Address of the offer asset
    /// @param minimumOrderSize Minimum order size for this asset
    event OfferAssetAdded(address indexed asset, uint256 minimumOrderSize);

    /// @notice Emitted when an offer asset is removed
    /// @param asset Address of the offer asset
    event OfferAssetRemoved(address indexed asset);

    /// @notice Emitted when a new want asset is added
    /// @param asset Address of the want asset
    event WantAssetAdded(address indexed asset);

    /// @notice Emitted when a want asset is removed
    /// @param asset Address of the want asset
    event WantAssetRemoved(address indexed asset);

    /// @notice Emitted when minimum order size is updated
    /// @param asset who's order size was updated
    /// @param oldMinimum Previous minimum order size
    /// @param newMinimum New minimum order size
    event MinimumOrderSizeUpdated(address asset, uint256 oldMinimum, uint256 newMinimum);

    /// @notice Emitted when boring vault address is updated
    /// @param oldVault Previous boring vault address
    /// @param newVault New boring vault address
    event BoringVaultUpdated(address indexed oldVault, address indexed newVault);

    // Order Events
    /// @notice Emitted when a new order is submitted
    /// @param orderIndex Index of the order in the queue (also the NFT token ID)
    /// @param order The order details
    /// @param receiver Address receiving the NFT receipt
    /// @param isSubmittedViaSignature True if order was submitted via signature
    event OrderSubmitted(
        uint256 indexed orderIndex, Order order, address indexed receiver, bool isSubmittedViaSignature
    );

    /// @notice Emitted when orders are processed
    /// @param startIndex Starting order index (inclusive)
    /// @param endIndex Ending order index (inclusive)
    event OrdersProcessed(uint256 indexed startIndex, uint256 indexed endIndex);

    /// @notice Emitted when an order is marked for refund
    /// @param orderIndex Index of the order
    /// @param order The order details
    event OrderMarkedForRefund(uint256 indexed orderIndex, Order order);

    /// @notice Emitted when an order is force processed
    /// @param orderIndex Index of the order
    /// @param order The order details
    /// @param receiver Address receiving the assets
    event OrderForceProcessed(uint256 indexed orderIndex, Order order, address indexed receiver);

    /// @notice Emitted when the fee recipient is updated
    /// @param oldFeeRecipient address
    /// @param newFeeRecipient address
    event FeeRecipientUpdated(address indexed oldFeeRecipient, address indexed newFeeRecipient);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

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
    /// @dev Initialized to 0, meaining the queue starts at 1. This makes the math less confusing with totalSupply() of
    uint256 public lastProcessedOrder;

    /// @notice represents the back of the queue, incremented on sumbiting orders
    uint256 public latestOrder;

    /// @notice Address of the fee module for calculating fees
    address public feeModule;

    /// @notice Address of the boring vault
    address public boringVault;

    /// @notice recipient of queue fees
    address public feeRecipient;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the contract
     * @param _name Name for the ERC721 receipt tokens
     * @param _symbol Symbol for the ERC721 receipt tokens
     * @param _boringVault Address of the boring vault
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _boringVault,
        address _feeModule,
        address _owner
    )
        ERC721(_name, _symbol)
        Auth(_owner, Authority(address(0)))
    {
        require(_boringVault != address(0), "Queue: boring vault is zero address");
        require(_owner != address(0), "Queue: owner is zero address");
        require(_feeModule != address(0), "Queue: fee module is zero address");

        boringVault = _boringVault;
        feeRecipient = _owner;
        feeModule = _feeModule;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the fee module address
     * @param _feeModule Address of the new fee module
     */
    function setFeeModule(address _feeModule) external requiresAuth {
        address oldFeeModule = feeModule;
        feeModule = _feeModule;
        emit FeeModuleUpdated(oldFeeModule, _feeModule);
    }

    /**
     * @notice Set the fee recipient address
     * @param _feeRecipient Address of the new fee module
     */
    function setFeeRecipient(address _feeRecipient) external requiresAuth {
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
        require(_asset != address(0), "Queue: asset is zero address");
        require(!supportedOfferAssets[_asset], "Queue: asset already supported");

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
        require(_asset != address(0), "Queue: asset is zero address");

        uint256 oldMinimum = minimumOrderSizePerAsset[_asset];
        minimumOrderSizePerAsset[_asset] = _newMinimum;

        emit MinimumOrderSizeUpdated(_asset, oldMinimum, _newMinimum);
    }
    /**
     * @notice Remove a supported offer asset
     * @param _asset Address of the offer asset to remove
     */

    function removeOfferAsset(address _asset) external requiresAuth {
        require(supportedOfferAssets[_asset], "Queue: asset not supported");

        supportedOfferAssets[_asset] = false;

        emit OfferAssetRemoved(_asset);
    }

    /**
     * @notice Add a supported want asset
     * @param _asset Address of the want asset to add
     */
    function addWantAsset(address _asset) external requiresAuth {
        require(_asset != address(0), "Queue: asset is zero address");
        require(!supportedWantAssets[_asset], "Queue: asset already supported");

        supportedWantAssets[_asset] = true;

        emit WantAssetAdded(_asset);
    }

    /**
     * @notice Remove a supported want asset
     * @param _asset Address of the want asset to remove
     */
    function removeWantAsset(address _asset) external requiresAuth {
        require(supportedWantAssets[_asset], "Queue: asset not supported");

        supportedWantAssets[_asset] = false;

        emit WantAssetRemoved(_asset);
    }

    /**
     * @notice Update boring vault address
     * @param _newVault Address of the new boring vault
     */
    function updateBoringVault(address _newVault) external requiresAuth {
        require(_newVault != address(0), "Queue: vault is zero address");

        address oldVault = boringVault;
        boringVault = _newVault;

        emit BoringVaultUpdated(oldVault, _newVault);
    }

    /**
     * @notice Mark an order for refund
     * @dev This does not burn the NFT, as the order is not "filed" until it's processed
     * @param orderIndex Index of the order to refund
     */
    function refund(uint256 orderIndex) external requiresAuth {
        require(orderIndex > lastProcessedOrder, "Cannot mark processed orders for refund");

        Order storage order = queue[orderIndex];
        require(order.status == Status.DEFAULT, "Queue: order not in default status");

        order.status = Status.REFUND;

        emit OrderMarkedForRefund(orderIndex, order);
    }

    /**
     * @notice Force process an order out of sequence
     * @param orderIndex Index of the order to force process
     */
    function forceProcess(uint256 orderIndex) external requiresAuth {
        require(orderIndex > lastProcessedOrder, "Cannot force process processed orders");

        Order storage order = queue[orderIndex];

        // If order was previously marked for refund, fill it as a refund and change to PRE_FILLED
        if (order.status == Status.REFUND) {
            order.status = Status.PRE_FILLED;
            IERC20(address(order.offerAsset)).safeTransfer(order.refundReceiver, order.amount);
            return;
        }

        // otherwise require order is set to DEFAULT status
        require(order.status == Status.DEFAULT, "Queue: order not in default status");

        // Mark as pre-filled
        order.status = Status.PRE_FILLED;

        Order[] memory orderArray;
        // set order as the processed version with want asset decimals
        orderArray[0] = _modifyAmountFromOfferToWantDecimals(order);

        IFeeModule.PostFeeProcessedOrder[] memory postFeeProcessedOrders;
        IERC20[] memory feeAssets;
        uint256[] memory feeAmounts;

        require(feeAssets.length == 0 && feeAmounts.length == 0, "array length missmatch");

        uint256[] memory orderIDs = new uint256[](1);
        orderIDs[0] = orderIndex;
        (postFeeProcessedOrders, feeAssets, feeAmounts) = IFeeModule(feeModule).calculateFees(orderArray, orderIDs);

        postFeeProcessedOrders[0].asset.safeTransfer(
            postFeeProcessedOrders[0].receiver, postFeeProcessedOrders[0].finalAmount
        );
        feeAssets[0].safeTransfer(feeRecipient, feeAmounts[0]);

        _burn(orderIndex);

        emit OrderForceProcessed(orderIndex, order, postFeeProcessedOrders[0].receiver);
    }

    /*//////////////////////////////////////////////////////////////
                         ORDER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function submitOrder(
        uint256 amount,
        ERC20 offerAsset,
        ERC20 wantAsset,
        address receiver,
        address refundReceiver,
        SubmissionParams calldata params
    )
        public
        returns (uint256 orderIndex)
    {
        require(supportedOfferAssets[address(offerAsset)], "Queue: offer asset not supported");
        require(supportedWantAssets[address(wantAsset)], "Queue: want asset not supported");
        require(amount >= minimumOrderSizePerAsset[address(offerAsset)], "Queue: amount below minimum");
        require(receiver != address(0), "Queue: receiver is zero address");
        require(refundReceiver != address(0), "Queue: refund receiver is zero address");
        require(block.timestamp <= params.deadline, "Queue: signature expired");

        address depositor;
        if (params.submitWithSignature) {
            bytes32 hash = keccak256(
                abi.encode(amount, offerAsset, wantAsset, receiver, refundReceiver, params.deadline, params.nonce)
            );
            require(!usedSignatureHashes[hash], "hash already used, re-sign with new nonce");
            usedSignatureHashes[hash] = true;

            depositor = ECDSA.recover(hash, params.eip2612Signature);
        } else {
            depositor = msg.sender;
        }

        // Do nothing if using standard ERC20 approve
        if (params.approvalMethod == ApprovalMethod.EIP2612_PERMIT) {
            ERC20(address(offerAsset)).permit(
                depositor, address(this), amount, params.deadline, params.approvalV, params.approvalR, params.approvalS
            );
        }
        IERC20(address(offerAsset)).safeTransferFrom(msg.sender, boringVault, amount);

        unchecked {
            orderIndex = ++latestOrder;
        }

        // Create order
        queue[orderIndex] = Order({
            amount: amount,
            offerAsset: offerAsset,
            wantAsset: wantAsset,
            refundReceiver: refundReceiver,
            status: Status.DEFAULT
        });

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
    function processOrders(uint256 ordersToProcess) public {
        require(ordersToProcess > 0, "Queue: must process at least one order");

        uint256 startIndex;
        uint256 endIndex;
        unchecked {
            startIndex = lastProcessedOrder + 1;
            endIndex = lastProcessedOrder + ordersToProcess;
        }

        // Ensure we don't go beyond existing orders
        require(endIndex <= latestOrder, "Queue: not enough orders to process");

        // Build arrays of orders for fee module
        Order[] memory ordersAmountsModifiedToWantAssetArray = new Order[](ordersToProcess);
        // Must keep track of order ids to send to the fee module, as PRE_FILLED or REFUND orders can mess up ordering
        uint256[] memory orderIDs = new uint256[](ordersToProcess);

        uint256 validOrdersCount;
        for (uint256 i; i < ordersToProcess; ++i) {
            uint256 orderIndex = startIndex + i;

            Order memory order = queue[orderIndex];

            if (order.status == Status.PRE_FILLED) {
                // ignore
                continue;
            }

            order = _modifyAmountFromOfferToWantDecimals(order);

            if (order.status == Status.REFUND) {
                // handle refund now since no need to adjust decimals or apply fees and ignore
                IERC20(address(order.offerAsset)).safeTransfer(order.refundReceiver, order.amount);
                continue;
            }

            unchecked {
                orderIndex = ++lastProcessedOrder;
            }
            ordersAmountsModifiedToWantAssetArray[validOrdersCount] = order;
            orderIDs[validOrdersCount++] = orderIndex;
        }

        IFeeModule.PostFeeProcessedOrder[] memory postFeeProcessedOrders;
        IERC20[] memory feeAssets;
        uint256[] memory feeAmounts;

        require(feeAssets.length == feeAmounts.length, "array length missmatch");

        (postFeeProcessedOrders, feeAssets, feeAmounts) =
            IFeeModule(feeModule).calculateFees(ordersAmountsModifiedToWantAssetArray, orderIDs);

        // TODO: Big one, change fees to be charged on submission not on process

        // Process each order
        for (uint256 i; i < postFeeProcessedOrders.length; ++i) {
            postFeeProcessedOrders[i].asset.safeTransfer(
                postFeeProcessedOrders[i].receiver, postFeeProcessedOrders[i].finalAmount
            );
            // burn NFTs after consulting fee module
            _burn(orderIDs[i]);
        }

        // Sent sees to fee recipient
        for (uint256 i; i < feeAssets.length; ++i) {
            feeAssets[i].safeTransfer(feeRecipient, feeAmounts[i]);
        }

        emit OrdersProcessed(startIndex, endIndex);
    }

    /**
     * @notice Submit and immediately process an order if liquidity is available
     * @param amount Amount of offer asset
     * @param offerAsset Asset being offered
     * @param wantAsset Asset being requested
     * @param receiver Address to receive the NFT receipt and want asset
     * @param refundReceiver Address to receive refunds if needed
     * @param params for submission signature use
     * @return orderIndex The index of the created order
     */
    function submitOrderAndProcess(
        uint256 amount,
        ERC20 offerAsset,
        ERC20 wantAsset,
        address receiver,
        address refundReceiver,
        SubmissionParams calldata params
    )
        external
        returns (uint256 orderIndex)
    {
        orderIndex = submitOrder(amount, offerAsset, wantAsset, receiver, refundReceiver, params);
        processOrders(orderIndex - lastProcessedOrder);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Modifies an order's amount from want decimals to offer decimals
     * @dev This is used to avoid storing another value in memory
     * return modifiedOrder
     */
    function _modifyAmountFromOfferToWantDecimals(Order memory order) internal returns (Order memory modifiedOrder) {
        modifiedOrder = order;
        uint8 offerDecimals = order.offerAsset.decimals();
        uint8 wantDecimals = order.wantAsset.decimals();

        if (offerDecimals == wantDecimals) {
            return modifiedOrder;
        }

        if (offerDecimals > wantDecimals) {
            uint8 difference = offerDecimals - wantDecimals;
            modifiedOrder.amount = order.amount / 10 ** difference;
            return modifiedOrder;
        }

        uint8 difference = wantDecimals - offerDecimals;
        modifiedOrder.amount = order.amount * 10 ** difference;
    }
}
