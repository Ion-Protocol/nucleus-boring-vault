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

        vm.expectEmit(true, true, true, true);
        emit Pausable.Paused(owner);
        rolesAuthority.pause();
        vm.stopPrank();

        assertTrue(rolesAuthority.paused());
        vm.stopPrank();

        vm.startPrank(user1);
        OneToOneQueue.SubmitOrderParams memory params =
            _createSubmitOrderParams(1e6, USDC, USDG0, user1, user1, user1, defaultParams);
        bytes memory data = abi.encodeWithSelector(OneToOneQueue.submitOrder.selector, params);
        vm.expectRevert(
            abi.encodeWithSelector(VerboseAuth.Unauthorized.selector, user1, data, "- Paused "), address(queue)
        );
        queue.submitOrder(params);
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
                abi.encodeWithSelector(AccessAuthority.continueDeprecation.selector),
                "- No Authority Set: Owner Only "
            ),
            address(rolesAuthority)
        );
        rolesAuthority.continueDeprecation();

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit AccessAuthority.DeprecationContinued(1);
        rolesAuthority.continueDeprecation();
        assertEq(rolesAuthority.deprecationStep(), 1);
        assertFalse(rolesAuthority.isFullyDeprecated());
        vm.stopPrank();

        vm.startPrank(user1);
        OneToOneQueue.SubmitOrderParams memory params =
            _createSubmitOrderParams(1e6, USDC, USDG0, user1, user1, user1, defaultParams);
        bytes memory data = abi.encodeWithSelector(OneToOneQueue.submitOrder.selector, params);
        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector, user1, data, "- Unauthorized - Deprecation in progress "
            ),
            address(queue)
        );
        queue.submitOrder(params);
        vm.stopPrank();
    }

    function test_continueDeprecation() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector,
                address(this),
                abi.encodeWithSelector(AccessAuthority.continueDeprecation.selector),
                "- No Authority Set: Owner Only "
            ),
            address(rolesAuthority)
        );
        rolesAuthority.continueDeprecation();

        _submitAnOrder();

        vm.startPrank(owner);
        rolesAuthority.continueDeprecation();

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
        OneToOneQueue.SubmitOrderParams memory params =
            _createSubmitOrderParams(1e6, USDC, USDG0, user1, user1, user1, defaultParams);
        bytes memory data = abi.encodeWithSelector(OneToOneQueue.submitOrder.selector, params);
        vm.expectRevert(
            abi.encodeWithSelector(
                VerboseAuth.Unauthorized.selector, user1, data, "- Paused - Unauthorized - Fully Deprecated "
            ),
            address(queue)
        );
        queue.submitOrder(params);

        data = abi.encodeWithSelector(OneToOneQueue.processOrders.selector, 1);
        vm.expectRevert(
            abi.encodeWithSelector(VerboseAuth.Unauthorized.selector, user1, data, "- Paused - Fully Deprecated "),
            address(queue)
        );
        queue.processOrders(1);

        vm.stopPrank();
    }

}
