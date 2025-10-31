// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { OneToOneQueue } from "src/helper/one-to-one-queue/OneToOneQueue.sol";
import { SimpleFeeModule } from "src/helper/one-to-one-queue/SimpleFeeModule.sol";
import { QueueAccessAuthority, AccessAuthority } from "src/helper/one-to-one-queue/QueueAccessAuthority.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { OneToOneQueueTestBase, tERC20, ERC20 } from "../OneToOneQueueTestBase.t.sol";

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
        vm.expectRevert("UNAUTHORIZED");
        rolesAuthority.pause();

        // Just test owner instead of a particular role
        vm.startPrank(owner);
        rolesAuthority.pause();
        assertTrue(rolesAuthority.paused());

        assertEq(uint8(rolesAuthority.pauseReason()), uint8(AccessAuthority.REASON.PAUSED_BY_PROTOCOL));

        // TODO: Expect a specific error. For now I'm usnure if I want a verbose error or not from canCall()
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessAuthority.AccessAuthority__paused.selector, AccessAuthority.REASON.PAUSED_BY_PROTOCOL, 0
            )
        );
        queue.submitOrder(1e6, USDC, USDG0, user1, user1, user1, defaultParams);
        vm.stopPrank();
    }

    function test_beginDeprecation() external {
        vm.expectRevert("UNAUTHORIZED");
        rolesAuthority.beginDeprecation();

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit AccessAuthority.DeprecationBegun(1);
        rolesAuthority.beginDeprecation();
        assertEq(rolesAuthority.deprecationStep(), 1);
        assertFalse(rolesAuthority.isFullyDeprecated());
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("UNAUTHORIZED");
        queue.submitOrder(1e6, USDC, USDG0, user1, user1, user1, defaultParams);
        vm.stopPrank();
    }

    function test_continueDeprecation() external {
        vm.expectRevert("UNAUTHORIZED");
        rolesAuthority.continueDeprecation();

        vm.startPrank(owner);
        vm.expectRevert(AccessAuthority.DeprecationNotBegun.selector);
        rolesAuthority.continueDeprecation();

        rolesAuthority.beginDeprecation();

        vm.expectEmit(true, true, true, true);
        emit AccessAuthority.DeprecationContinued(2);
        emit AccessAuthority.DeprecationFinished(2);
        rolesAuthority.continueDeprecation();

        assertEq(rolesAuthority.deprecationStep(), 2);
        assertEq(uint8(rolesAuthority.pauseReason()), uint8(AccessAuthority.REASON.DEPRECATED));
        assertTrue(rolesAuthority.isFullyDeprecated());
        assertTrue(rolesAuthority.paused());
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessAuthority.AccessAuthority__paused.selector, AccessAuthority.REASON.DEPRECATED, 2
            )
        );
        queue.submitOrder(1e6, USDC, USDG0, user1, user1, user1, defaultParams);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessAuthority.AccessAuthority__paused.selector, AccessAuthority.REASON.DEPRECATED, 2
            )
        );
        queue.processOrders(1);

        vm.stopPrank();
    }

}
