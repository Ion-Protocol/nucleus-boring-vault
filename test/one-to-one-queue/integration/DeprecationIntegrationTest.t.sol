// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { OneToOneQueue } from "src/helper/one-to-one-queue/OneToOneQueue.sol";
import { SimpleFeeModule } from "src/helper/one-to-one-queue/SimpleFeeModule.sol";
import { QueueAccessAuthority } from "src/helper/one-to-one-queue/QueueAccessAuthority.sol";
import { OneToOneQueueTestBase, tERC20, ERC20 } from "../OneToOneQueueTestBase.t.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { AccessAuthority } from "src/helper/one-to-one-queue/abstract/AccessAuthority.sol";
import { VerboseAuth } from "src/helper/one-to-one-queue/abstract/VerboseAuth.sol";

contract DeprecationStep1IntegrationTest is OneToOneQueueTestBase {

    modifier givenContractStartsDeprecation() {
        vm.startPrank(owner);
        rolesAuthority.beginDeprecation();
        vm.stopPrank();
        _;
    }

    function test_submitOrderAndProcessRevertsWhenContractIsDeprecatedForAllButOwner()
        external
        givenContractStartsDeprecation
    {
        vm.startPrank(user1);
        bytes memory data = abi.encodeWithSelector(
            OneToOneQueue.submitOrderAndProcess.selector, 1e6, USDC, USDG0, user1, user1, user1, defaultParams
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector,
                user1,
                OneToOneQueue.submitOrderAndProcess.selector,
                data,
                "- Deprecation in progress "
            ),
            address(queue)
        );
        queue.submitOrderAndProcess(1e6, USDC, USDG0, user1, user1, user1, defaultParams);
        vm.stopPrank();

        vm.startPrank(owner);
        deal(address(USDC), owner, 1e6);
        deal(address(USDG0), address(queue), 1e6);
        USDC.approve(address(queue), 1e6);
        vm.expectEmit(true, true, true, true);
        emit OrdersProcessed(1, 1);
        queue.submitOrderAndProcess(1e6, USDC, USDG0, owner, owner, owner, defaultParams);
        vm.stopPrank();
    }

    function test_submitOrderRevertsWhenContractIsDeprecatedForAllButOwner() external givenContractStartsDeprecation {
        vm.startPrank(user1);
        bytes memory data = abi.encodeWithSelector(
            OneToOneQueue.submitOrder.selector, 1e6, USDC, USDG0, user1, user1, user1, defaultParams
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector,
                user1,
                OneToOneQueue.submitOrder.selector,
                data,
                "- Deprecation in progress "
            ),
            address(queue)
        );
        queue.submitOrder(1e6, USDC, USDG0, user1, user1, user1, defaultParams);
        vm.stopPrank();

        vm.startPrank(owner);
        deal(address(USDC), owner, 1e6);
        USDC.approve(address(queue), 1e6);
        queue.submitOrder(1e6, USDC, USDG0, owner, owner, owner, defaultParams);
        assertEq(queue.ownerOf(1), owner);
        vm.stopPrank();
    }

    function test_processOrdersPassesWhenContractIsOnlyOnDeprecationStep1() external {
        _submitAnOrder();
        deal(address(USDG0), address(queue), 1e6);

        vm.startPrank(owner);
        rolesAuthority.beginDeprecation();
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectEmit(true, true, true, true);
        emit OrdersProcessed(1, 1);
        queue.processOrders(1);
        vm.stopPrank();
    }

}

contract DeprecationStep2IntegrationTest is OneToOneQueueTestBase {

    modifier givenContractFinishesDeprecation() {
        vm.startPrank(owner);
        rolesAuthority.beginDeprecation();
        rolesAuthority.continueDeprecation();
        vm.stopPrank();
        _;
    }

    function test_submitOrderAndProcessRevertsWhenContractIsDeprecatedForAllButOwner()
        external
        givenContractFinishesDeprecation
    {
        vm.startPrank(user1);
        bytes memory data = abi.encodeWithSelector(
            OneToOneQueue.submitOrderAndProcess.selector, 1e6, USDC, USDG0, user1, user1, user1, defaultParams
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector,
                user1,
                OneToOneQueue.submitOrderAndProcess.selector,
                data,
                "- Paused - Fully Deprecated "
            ),
            address(queue)
        );
        queue.submitOrderAndProcess(1e6, USDC, USDG0, user1, user1, user1, defaultParams);
        vm.stopPrank();

        vm.startPrank(owner);
        deal(address(USDC), owner, 1e6);
        deal(address(USDG0), address(queue), 1e6);
        USDC.approve(address(queue), 1e6);
        vm.expectEmit(true, true, true, true);
        emit OrdersProcessed(1, 1);
        queue.submitOrderAndProcess(1e6, USDC, USDG0, owner, owner, owner, defaultParams);
        vm.stopPrank();
    }

    function test_submitOrderRevertsWhenContractIsDeprecatedForAllButOwner() external givenContractFinishesDeprecation {
        vm.startPrank(user1);
        bytes memory data = abi.encodeWithSelector(
            OneToOneQueue.submitOrder.selector, 1e6, USDC, USDG0, user1, user1, user1, defaultParams
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector,
                user1,
                OneToOneQueue.submitOrder.selector,
                data,
                "- Paused - Fully Deprecated "
            ),
            address(queue)
        );
        queue.submitOrder(1e6, USDC, USDG0, user1, user1, user1, defaultParams);
        vm.stopPrank();

        vm.startPrank(owner);
        deal(address(USDC), owner, 1e6);
        USDC.approve(address(queue), 1e6);
        queue.submitOrder(1e6, USDC, USDG0, owner, owner, owner, defaultParams);
        assertEq(queue.ownerOf(1), owner);
        vm.stopPrank();
    }

    function test_cannotFullyDeprecateWithOrdersInTheQueue() external {
        _submitAnOrder();

        vm.startPrank(owner);
        rolesAuthority.beginDeprecation();
        vm.expectRevert(abi.encodeWithSelector(QueueAccessAuthority.QueueNotEmpty.selector), address(rolesAuthority));
        rolesAuthority.continueDeprecation();
        vm.stopPrank();
    }

    function test_processOrdersFailsWhenFullyDeprecatedForAllButOwner() external givenContractFinishesDeprecation {
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector,
                user1,
                OneToOneQueue.processOrders.selector,
                abi.encodeWithSelector(OneToOneQueue.processOrders.selector, 1),
                "- Paused - Fully Deprecated "
            ),
            address(queue)
        );
        queue.processOrders(1);
        vm.stopPrank();

        // No emit since there should be no orders in the queue
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(OneToOneQueue.NotEnoughOrdersToProcess.selector, 1, 0), address(queue));
        queue.processOrders(1);
        vm.stopPrank();
    }

}
