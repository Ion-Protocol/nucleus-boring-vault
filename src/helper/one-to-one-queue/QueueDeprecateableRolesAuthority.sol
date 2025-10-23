// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { DeprecatableRolesAuthority, RolesAuthority } from "./abstract/DeprecatableRolesAuthority.sol";
import { OneToOneQueue } from "./OneToOneQueue.sol";
import { Authority } from "@solmate/auth/Auth.sol";

contract QueueDeprecateableRolesAuthority is DeprecatableRolesAuthority {
    address public queue;

    constructor(address _owner, address _queue) RolesAuthority(_owner, Authority(address(0))) {
        queue = _queue;
        // TODO: Right now only owner can call these functions, so only owner may deploy... see if there's an internal
        // function
        setPublicCapability(queue, OneToOneQueue.processOrders.selector, true);
        setPublicCapability(queue, OneToOneQueue.submitOrder.selector, true);
        setPublicCapability(queue, OneToOneQueue.submitOrderAndProcess.selector, true);
    }

    /// @dev 2 deprecation steps
    /// 1: Dissable new orders but allow solving existing ones
    /// 2: Dissable everything via a pause. But ensure the queue is empty
    enum DEPRECATION_STEP {
        NOT_DEPRECATED,
        NO_NEW_ORDERS,
        CLOSED
    }

    error QueueDeprecateableRolesAuthority__QueueNotEmpty();

    /// @dev Step 1
    function _onDeprecationBegin() internal override {
        setPublicCapability(queue, OneToOneQueue.submitOrder.selector, false);
        setPublicCapability(queue, OneToOneQueue.submitOrderAndProcess.selector, false);
    }

    /// @dev Step 2
    function _onDeprecationContinue(uint8 newStep) internal override {
        // TODO: Validate that even when pre-filling the totoalSupply is still a valid count of outstanding orders
        if (OneToOneQueue(queue).totalSupply() != 0) {
            revert QueueDeprecateableRolesAuthority__QueueNotEmpty();
        }
        isFullyDeprecated = true;
        _pauseForDeprecation();
    }
}
