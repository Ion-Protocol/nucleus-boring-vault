// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { OneToOneQueue } from "src/helper/one-to-one-queue/OneToOneQueue.sol";
import { SimpleFeeModule } from "src/helper/one-to-one-queue/SimpleFeeModule.sol";
import { QueueAccessAuthority } from "src/helper/one-to-one-queue/QueueAccessAuthority.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

/// NOTE: We need to deploy the Solmate ERC20 since the OZ ERC20Permit has a dependency with solidity version 0.8.24 and
/// cannot be used with our contracts
import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract tERC20 is ERC20 {

    constructor(uint8 _decimalsInput) ERC20("test name", "test", _decimalsInput) { }

}

abstract contract OneToOneQueueTestBase is Test {

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
    event OfferAssetRecipientUpdated(address indexed oldVault, address indexed newVault);

    // Order Events
    /// @notice Emitted when a new order is submitted
    /// @param orderIndex Index of the order in the queue (also the NFT token ID)
    /// @param order The order details
    /// @param receiver Address receiving the NFT receipt
    /// @param isSubmittedViaSignature True if order was submitted via signature
    event OrderSubmitted(
        uint256 indexed orderIndex, OneToOneQueue.Order order, address indexed receiver, bool isSubmittedViaSignature
    );

    /// @notice Emitted when orders are processed
    /// @param startIndex Starting order index (inclusive)
    /// @param endIndex Ending order index (inclusive)
    event OrdersProcessed(uint256 indexed startIndex, uint256 indexed endIndex);

    /// @notice Emitted when an order is refunded
    /// @param orderIndex Index of the order
    /// @param order The order details
    event OrderRefunded(uint256 indexed orderIndex, OneToOneQueue.Order order);

    /// @notice Emitted when an order is force processed
    /// @param orderIndex Index of the order
    /// @param order The order details
    /// @param receiver Address receiving the assets
    event OrderForceProcessed(uint256 indexed orderIndex, OneToOneQueue.Order order, address indexed receiver);

    /// @notice Emitted when the fee recipient is updated
    /// @param oldFeeRecipient address
    /// @param newFeeRecipient address
    event FeeRecipientUpdated(address indexed oldFeeRecipient, address indexed newFeeRecipient);

    OneToOneQueue queue;
    SimpleFeeModule feeModule;
    QueueAccessAuthority rolesAuthority;

    IERC20 public USDC;
    IERC20 public USDG0;
    IERC20 public DAI;

    uint256 TEST_OFFER_FEE_PERCENTAGE = 10; // 0.1% fee

    address mockBoringVaultAddress = makeAddr("boring vault");
    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address solver = makeAddr("solver");
    address feeRecipient = makeAddr("fee recipient");
    address alice;
    uint256 alicePk;

    // A simple params struct used in most tests
    OneToOneQueue.SubmissionParams defaultParams = OneToOneQueue.SubmissionParams({
        approvalMethod: OneToOneQueue.ApprovalMethod.EIP20_APROVE,
        approvalV: 0,
        approvalR: bytes32(0),
        approvalS: bytes32(0),
        submitWithSignature: false,
        deadline: block.timestamp + 1000,
        eip2612Signature: "",
        nonce: 0
    });

    function setUp() external {
        vm.startPrank(owner);
        feeModule = new SimpleFeeModule(TEST_OFFER_FEE_PERCENTAGE);
        queue = new OneToOneQueue("name", "symbol", mockBoringVaultAddress, feeRecipient, feeModule, owner);
        rolesAuthority = new QueueAccessAuthority(owner, address(queue));

        (alice, alicePk) = makeAddrAndKey("alice");

        queue.setAuthority(rolesAuthority);

        USDC = IERC20(address(new tERC20(6)));
        USDG0 = IERC20(address(new tERC20(6)));
        DAI = IERC20(address(new tERC20(18)));

        queue.addOfferAsset(address(USDC), 0);
        queue.addWantAsset(address(USDG0));
        vm.stopPrank();
    }

    function _submitAnOrder() internal {
        deal(address(USDC), user1, 1e6);
        vm.startPrank(user1);
        USDC.approve(address(queue), 1e6);
        queue.submitOrder(1e6, USDC, USDG0, user1, user1, user1, defaultParams);
        vm.stopPrank();

        assertTrue(queue.ownerOf(1) == user1, "_sumbitAnOrder: user1 should be the owner of the order");
    }

    function _getPermitSignature(
        IERC20 token,
        address owner,
        uint256 ownerPk,
        address spender,
        uint256 value,
        uint256 deadline
    )
        internal
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                IERC20Permit(address(token)).DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        owner,
                        spender,
                        value,
                        IERC20Permit(address(token)).nonces(owner),
                        deadline
                    )
                )
            )
        );
        (v, r, s) = vm.sign(ownerPk, permitHash);
    }

}
