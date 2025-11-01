// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { OneToOneQueue } from "src/helper/one-to-one-queue/OneToOneQueue.sol";
import { SimpleFeeModule } from "src/helper/one-to-one-queue/SimpleFeeModule.sol";
import { QueueAccessAuthority, AccessAuthority } from "src/helper/one-to-one-queue/QueueAccessAuthority.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { OneToOneQueueTestBase, tERC20, ERC20 } from "../OneToOneQueueTestBase.t.sol";
import { VerboseAuth } from "src/helper/one-to-one-queue/abstract/VerboseAuth.sol";

contract AccessAuthorityTest is OneToOneQueueTestBase {

    /// @notice Emitted when deprecation process begins
    /// @param step The deprecation step number
    event DeprecationBegun(uint8 step);

    /// @notice Emitted when deprecation continues to next step
    /// @param newStep The new deprecation step
    event DeprecationContinued(uint8 newStep);

    /// @notice Emitted when deprecation is finalized
    /// @param newStep The new deprecation step
    event DeprecationFinished(uint8 newStep);

    function test_pause() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessAuthority.Unauthorized.selector,
                address(this),
                address(rolesAuthority),
                bytes4(keccak256("pause()"))
            ),
            address(rolesAuthority)
        );
        rolesAuthority.pause();

        // Just test owner instead of a particular role
        vm.startPrank(owner);
        rolesAuthority.pause();
        assertTrue(rolesAuthority.paused());
        vm.stopPrank();

        // TODO: Right now the owner can bypass all of the checks.... Think about this
        // Since canCall() is used not a full override
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
    }

    function test_beginDeprecation() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessAuthority.Unauthorized.selector,
                address(this),
                address(rolesAuthority),
                bytes4(keccak256("beginDeprecation()"))
            ),
            address(rolesAuthority)
        );
        rolesAuthority.beginDeprecation();

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit AccessAuthority.DeprecationBegun(1);
        rolesAuthority.beginDeprecation();
        assertEq(rolesAuthority.deprecationStep(), 1);
        assertFalse(rolesAuthority.isFullyDeprecated());
        vm.stopPrank();

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
    }

    function test_continueDeprecation() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessAuthority.Unauthorized.selector,
                address(this),
                address(rolesAuthority),
                bytes4(keccak256("continueDeprecation()"))
            ),
            address(rolesAuthority)
        );
        rolesAuthority.continueDeprecation();

        vm.prank(owner);
        vm.expectRevert(AccessAuthority.DeprecationNotBegun.selector, address(rolesAuthority));
        rolesAuthority.continueDeprecation();

        _submitAnOrder();

        vm.startPrank(owner);
        rolesAuthority.beginDeprecation();

        vm.expectRevert(abi.encodeWithSelector(QueueAccessAuthority.QueueNotEmpty.selector), address(rolesAuthority));
        rolesAuthority.continueDeprecation();

        deal(address(USDG0), address(queue), 1e6);
        queue.processOrders(1);

        vm.expectEmit(true, true, true, true);
        emit AccessAuthority.DeprecationContinued(2);
        emit AccessAuthority.DeprecationFinished(2);
        rolesAuthority.continueDeprecation();

        assertEq(rolesAuthority.deprecationStep(), 2);
        assertTrue(rolesAuthority.isFullyDeprecated());
        assertTrue(rolesAuthority.paused());
        vm.stopPrank();

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

        data = abi.encodeWithSelector(OneToOneQueue.processOrders.selector, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector,
                user1,
                OneToOneQueue.processOrders.selector,
                data,
                "- Paused - Fully Deprecated "
            ),
            address(queue)
        );
        queue.processOrders(1);

        vm.stopPrank();
    }

}
