// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { OneToOneQueue } from "src/helper/one-to-one-queue/OneToOneQueue.sol";
import { SimpleFeeModule } from "src/helper/one-to-one-queue/SimpleFeeModule.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
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
                VerboseAuth.Unauthorized.selector,
                address(this),
                AccessAuthority.pause.selector,
                abi.encodeWithSelector(AccessAuthority.pause.selector),
                "- Not a pauser or owner "
            ),
            address(rolesAuthority)
        );
        rolesAuthority.pause();

        // Pauser1 can pause
        vm.startPrank(pauser1);
        vm.expectEmit(true, true, true, true);
        emit Pausable.Paused(pauser1);
        rolesAuthority.pause();
        vm.stopPrank();

        // Owner can also pause but must unpause first
        vm.startPrank(owner);
        rolesAuthority.unpause(); /// TODO: This isn't ideal. We like to be able to have pauses go through even if
        /// already paused, but this is a feature of OZs Pausable and perhaps we like the standard usage more
        vm.expectEmit(true, true, true, true);
        emit Pausable.Paused(owner);
        rolesAuthority.pause();
        vm.stopPrank();

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

    function test_unpause() external {
        vm.startPrank(pauser1);
        rolesAuthority.pause();
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit Pausable.Unpaused(owner);
        rolesAuthority.unpause();
        vm.stopPrank();

        assertFalse(rolesAuthority.paused());
    }

    function test_beginDeprecation() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector,
                address(this),
                AccessAuthority.beginDeprecation.selector,
                abi.encodeWithSelector(AccessAuthority.beginDeprecation.selector),
                ""
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
                VerboseAuth.Unauthorized.selector,
                address(this),
                AccessAuthority.continueDeprecation.selector,
                abi.encodeWithSelector(AccessAuthority.continueDeprecation.selector),
                ""
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

    function test_setUsersBlacklistStatus() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector,
                address(this),
                QueueAccessAuthority.setUsersBlacklistStatus.selector,
                abi.encodeWithSelector(
                    QueueAccessAuthority.setUsersBlacklistStatus.selector, new address[](0), new bool[](0)
                ),
                ""
            ),
            address(rolesAuthority)
        );
        rolesAuthority.setUsersBlacklistStatus(new address[](0), new bool[](0));

        address[] memory blacklist = new address[](1);
        blacklist[0] = user2;
        bool[] memory isBlacklisted = new bool[](1);
        isBlacklisted[0] = true;

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit QueueAccessAuthority.BlacklistUpdated(user2, true);
        rolesAuthority.setUsersBlacklistStatus(blacklist, isBlacklisted);
        vm.stopPrank();

        assertTrue(rolesAuthority.isBlacklisted(user2));

        vm.startPrank(user2);
        bytes memory data = abi.encodeWithSelector(
            OneToOneQueue.submitOrder.selector, 1e6, USDC, USDG0, user2, user2, user2, defaultParams
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector, user2, OneToOneQueue.submitOrder.selector, data, "- Blacklisted "
            ),
            address(queue)
        );
        queue.submitOrder(1e6, USDC, USDG0, user2, user2, user2, defaultParams);
        vm.stopPrank();
    }

}
