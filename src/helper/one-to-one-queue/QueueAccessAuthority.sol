// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AccessAuthority, Authority, IAccessAuthorityHook } from "./access/AccessAuthority.sol";
import { OneToOneQueue } from "./OneToOneQueue.sol";

/**
 * @title QueueAccessAuthority
 * @notice An access authority for the OneToOneQueue contract
 * @dev The Following are the deprecation steps of the OneToOneQueue system:
 * Contracts:
 * - OneToOneQueue
 *
 * Steps:
 * 1: Disable public capability on submitOrder and submitOrderAndProcess to prevent placing new orders. Allow processing
 * of orders.
 * 2: Ensure the queue is empty. Disable all calls to requiresAuthVerbose modified functions via a pause.
 */
contract QueueAccessAuthority is AccessAuthority {

    address public immutable queue;

    error QueueNotEmpty();

    /// @dev Authority is set to 0 to keep this as owner only authority
    constructor(
        address _owner,
        address _queue,
        address[] memory defaultPausers
    )
        AccessAuthority(_owner, Authority(address(0)), IAccessAuthorityHook(address(0)), defaultPausers)
    {
        queue = _queue;

        // Initialize the roles for the queue
        _setPublicCapability(queue, OneToOneQueue.processOrders.selector, true);
        _setPublicCapability(queue, OneToOneQueue.submitOrder.selector, true);
        _setPublicCapability(queue, OneToOneQueue.submitOrderAndProcess.selector, true);
        _setPublicCapability(queue, OneToOneQueue.submitOrderAndProcessAll.selector, true);
    }

    /// @notice required override defining deprecation steps
    function totalDeprecationSteps() public view override returns (uint8) {
        return 2;
    }

    /// @notice handle deprecation for queue contract
    function _onDeprecationContinue(uint8 newStep) internal override {
        if (newStep == 1) {
            _setPublicCapability(queue, OneToOneQueue.submitOrder.selector, false);
            _setPublicCapability(queue, OneToOneQueue.submitOrderAndProcess.selector, false);
            _setPublicCapability(queue, OneToOneQueue.submitOrderAndProcessAll.selector, false);
        } else if (newStep == 2) {
            if (OneToOneQueue(queue).totalSupply() != 0) {
                revert QueueNotEmpty();
            }
            _pause();
        }
    }

}
