// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { OneToOneQueue } from "src/helper/one-to-one-queue/OneToOneQueue.sol";
import { SimpleFeeModule } from "src/helper/one-to-one-queue/SimpleFeeModule.sol";
import { QueueDeprecateableRolesAuthority } from "src/helper/one-to-one-queue/QueueDeprecateableRolesAuthority.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

contract tERC20 is ERC20 {

    constructor(uint8 decimals) ERC20("test name", "test", decimals) { }

}

/// TODO: test the gas of processing, how many can be processed? Should we remove fee module calls on process for
/// simplicity
contract OneToOneQueueTestHappyPath is Test {

    OneToOneQueue queue;
    SimpleFeeModule feeModule;
    QueueDeprecateableRolesAuthority rolesAuthority;

    ERC20 public USDC;
    ERC20 public USDG0;
    ERC20 public DAI;

    uint256 TEST_OFFER_FEE_PERCENTAGE = 10; // 0.1% fee

    address mockBoringVaultAddress = makeAddr("boring vault");
    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address solver = makeAddr("solver");
    address feeRecipient = makeAddr("fee recipient");

    // A simple params struct used in most tests
    OneToOneQueue.SubmissionParams params = OneToOneQueue.SubmissionParams({
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
        rolesAuthority = new QueueDeprecateableRolesAuthority(owner, address(queue));

        queue.setAuthority(rolesAuthority);

        USDC = new tERC20(6);
        USDG0 = new tERC20(6);
        DAI = new tERC20(18);

        queue.addOfferAsset(address(USDC), 0);
        queue.addWantAsset(address(USDG0));
    }

    /**
     * Queue Happy Path:
     * User Submits an order
     * A few more users submit orders of same asset
     * A solver fails to fill
     * Some assets are sent in to the contract
     * A solver fills an order
     * A user submits and fills their order automatically (filling all the others)
     *
     * All users should get back exactly how much they put in - fees
     * Fee receiver should get the total amount users deposit * feePercent
     * The totalSupply() should be 0 after all this
     */
    function testQueueHappyPath() external {
        // Test values
        uint256 depositAmount1 = 1e6;
        uint256 depositAmount2 = 2e6;
        uint256 depositAmount3 = 3e6;
        uint256 totalFees;

        // set up balances
        deal(address(USDC), user1, depositAmount1);
        deal(address(USDC), user2, depositAmount2);
        deal(address(USDC), user3, depositAmount3);

        // User1 submits an order
        vm.startPrank(user1);
        USDC.approve(address(queue), depositAmount1);
        queue.submitOrder(depositAmount1, USDC, USDG0, user1, user1, user1, params);
        vm.stopPrank();

        assertEq(queue.ownerOf(1), user1, "user1 should own NFT ID 1");
        assertEq(queue.totalSupply(), 1, "total supply should be 1 after first mint");

        // User2 sumbits an order
        vm.startPrank(user2);
        USDC.approve(address(queue), depositAmount2);
        queue.submitOrder(depositAmount2, USDC, USDG0, user2, user2, user2, params);
        vm.stopPrank();

        // User3 sumbits an order
        vm.startPrank(user3);
        USDC.approve(address(queue), depositAmount3);
        queue.submitOrder(depositAmount3, USDC, USDG0, user3, user3, user3, params);
        vm.stopPrank();

        assertEq(queue.ownerOf(2), user2, "user2 should own NFT ID 2");
        assertEq(queue.ownerOf(3), user3, "user3 should own NFT ID 3");
        assertEq(queue.totalSupply(), 3, "total supply should be 3 after 3 mints");

        // Solver fails to fill
        vm.startPrank(solver);
        vm.expectRevert(
            abi.encodeWithSelector(
                OneToOneQueue.InsufficientBalance.selector,
                1,
                address(queue),
                address(USDG0),
                1e6 - (1e6 * TEST_OFFER_FEE_PERCENTAGE / 10_000),
                0
            )
        );
        queue.processOrders(3);
        vm.stopPrank();

        // Deal assets to contract
        deal(address(USDG0), address(queue), 7e6);

        // Solve the first order only
        vm.prank(solver);
        queue.processOrders(1);

        uint256 user1Fees = 1e6 * TEST_OFFER_FEE_PERCENTAGE / 10_000;
        totalFees += user1Fees;
        uint256 user2Fees = 2e6 * TEST_OFFER_FEE_PERCENTAGE / 10_000;
        totalFees += user2Fees;
        uint256 user3Fees = 3e6 * TEST_OFFER_FEE_PERCENTAGE / 10_000;
        totalFees += user3Fees;

        assertEq(queue.totalSupply(), 2, "total supply should be 2 after 1 solve");
        assertEq(USDG0.balanceOf(user1), 1e6 - user1Fees, "User1 should have received their 1 USDG0 - fees");
        assertEq(USDC.balanceOf(feeRecipient), totalFees, "Fee receiver should have received fees");

        // User1 now deposit and sovles atomically to get all orders solved including their new one
        deal(address(USDC), user1, depositAmount1);
        vm.startPrank(user1);
        USDC.approve(address(queue), depositAmount1);
        queue.submitOrderAndProcess(depositAmount1, USDC, USDG0, user1, user1, user1, params);
        vm.stopPrank();

        totalFees += user1Fees;

        assertEq(queue.totalSupply(), 0, "total supply should be 0 after submitAndSolve");
        assertEq(USDG0.balanceOf(user2), 2e6 - user2Fees, "User2 should have received their 2 USDG0 - fees");
        assertEq(USDG0.balanceOf(user3), 3e6 - user3Fees, "User3 should have received their 3 USDG0 - fees");
        assertEq(USDC.balanceOf(feeRecipient), totalFees, "Fee receiver should have received fees");
        assertEq(
            USDG0.balanceOf(user1),
            2e6 - (2 * user1Fees),
            "User1 should have received their 2 USDG0 total - 2x fees (2 transactions)"
        );
        assertEq(USDC.balanceOf(address(queue)), 0, "Contract should have no more USDC");
        vm.stopPrank();
    }

    function testAssetsOfDifferentDecimals() external {
        uint256 depositAmount1 = 1e18;
        uint256 depositAmount2 = 1e6;

        vm.startPrank(owner);
        queue.addOfferAsset(address(DAI), 0);
        vm.stopPrank();

        deal(address(DAI), user1, 1e18);

        uint256 user1FeesWant = 1e6 * TEST_OFFER_FEE_PERCENTAGE / 10_000;
        uint256 user1FeesOffer = 1e18 * TEST_OFFER_FEE_PERCENTAGE / 10_000;
        deal(address(USDG0), address(queue), 1e6 - user1FeesWant);

        vm.startPrank(user1);
        DAI.approve(address(queue), 1e18);
        queue.submitOrderAndProcess(depositAmount1, DAI, USDG0, user1, user1, user1, params);
        vm.stopPrank();

        assertEq(USDG0.balanceOf(user1), 1e6 - user1FeesWant, "User should have received USDG0 in 6 decimals");
        assertEq(DAI.balanceOf(feeRecipient), user1FeesOffer, "Fee Recipient should have received DAI in 18 decimals");
    }

    function testDeprecation() external {
        vm.startPrank(user1);
        vm.expectRevert("UNAUTHORIZED");
        rolesAuthority.beginDeprecation();
        vm.stopPrank();

        vm.startPrank(owner);
        rolesAuthority.beginDeprecation();

        deal(address(USDC), owner, 11e6);
        deal(address(USDG0), address(queue), 11e6);
        USDC.approve(address(queue), 11e6);
        vm.stopPrank();

        vm.startPrank(user1);

        deal(address(USDC), user1, 11e6);
        USDC.approve(address(queue), 11e6);
        vm.expectRevert("UNAUTHORIZED");
        queue.submitOrder(1e6, USDC, USDG0, user1, user1, user1, params);

        vm.stopPrank();

        vm.startPrank(owner);
        queue.submitOrder(1e6, USDC, USDG0, owner, owner, owner, params);
        assertEq(queue.ownerOf(1), owner, "owner could mint because deprecation doesn't apply to the owner");
        vm.stopPrank();

        vm.startPrank(user1);
        queue.processOrders(1);
        assertTrue(true, "This should pass as the orders can still be solved");
        vm.stopPrank();

        vm.startPrank(owner);
        rolesAuthority.continueDeprecation();
        vm.stopPrank();

        vm.prank(user1);
        // TODO: upgrade to custom errors and confirm it's that
        vm.expectRevert();
        queue.processOrders(1);
        vm.stopPrank();
    }

    function testRefund() external {
        deal(address(USDC), user1, 11e6);
        vm.startPrank(user1);
        USDC.approve(address(queue), 11e6);

        deal(address(USDC), address(queue), 11e6);
        deal(address(USDG0), address(queue), 11e6);

        // user submits 3 orders
        // Make user2 the receiver of 1 and 3 so easier to measure the result of the processing
        queue.submitOrder(1e6, USDC, USDG0, user1, user2, user2, params);
        queue.submitOrder(2e6, USDC, USDG0, user1, user1, user1, params);
        queue.submitOrder(3e6, USDC, USDG0, user1, user2, user2, params);
        vm.stopPrank();

        // owner refunds 1
        uint256 balanceUSDCBefore = USDC.balanceOf(user1);

        // Refund the second order
        vm.startPrank(owner);
        queue.forceRefund(2);

        vm.stopPrank();
        assertEq(
            USDC.balanceOf(user1) - balanceUSDCBefore,
            2e6,
            "User should just have their 2 USDC balance back including fees paid: note this is excess in the queue in this test as the fee receiver receives this amount"
        );
        assertEq(USDG0.balanceOf(user1), 0, "User should have no USDG0");

        // Process the orders
        queue.processOrders(3);
        assertEq(USDC.balanceOf(user1) - balanceUSDCBefore, 2e6, "User should have no more USDC");
        assertEq(USDG0.balanceOf(user1), 0, "User should have no USDG0 because they were refunded");
    }

    function testPreFill() external { }

    function testFuzzOrders() external { }

}
