// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { OneToOneQueue } from "src/helper/one-to-one-queue/OneToOneQueue.sol";
import { SimpleFeeModule } from "src/helper/one-to-one-queue/SimpleFeeModule.sol";
import { OneToOneQueueTestBase, tERC20, ERC20 } from "../OneToOneQueueTestBase.t.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { AccessAuthority } from "src/helper/one-to-one-queue/abstract/AccessAuthority.sol";
import { VerboseAuth } from "src/helper/one-to-one-queue/abstract/VerboseAuth.sol";

contract PauseQueueIntegrationTest is OneToOneQueueTestBase {

    modifier givenContractIsPaused() {
        vm.prank(pauser1);
        rolesAuthority.pause();
        _;
    }

    // Not testing admin functions such as setters. Only owner may call them anyways, and owners bypass pause. Therefore
    // they would all just behave as expected anyways.
    function test_submitOrderAndProcessRevertsWhenContractIsPausedForAllButOwner() external givenContractIsPaused {
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
                "- Paused "
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

    function test_submitOrderRevertsWhenContractIsPausedForAllButOwner() external givenContractIsPaused {
        vm.startPrank(user1);

        bytes memory data = abi.encodeWithSelector(
            OneToOneQueue.submitOrder.selector, 1e6, USDC, USDG0, user1, user1, user1, defaultParams
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector, user1, OneToOneQueue.submitOrder.selector, data, "- Paused "
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

    function test_processOrdersRevertsWhenContractIsPausedForAllButOwner() external {
        _submitAnOrder();

        vm.prank(pauser1);
        rolesAuthority.pause();

        vm.startPrank(user1);
        bytes memory data = abi.encodeWithSelector(OneToOneQueue.processOrders.selector, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector, user1, OneToOneQueue.processOrders.selector, data, "- Paused "
            ),
            address(queue)
        );
        queue.processOrders(1);
        vm.stopPrank();

        vm.startPrank(owner);
        deal(address(USDG0), address(queue), 1e6);
        vm.expectEmit(true, true, true, true);
        emit OrdersProcessed(1, 1);
        queue.processOrders(1);
        vm.stopPrank();
    }

}
