// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AccessAuthority, Authority } from "./abstract/AccessAuthority.sol";
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

    address public queue;

    error QueueNotEmpty();

    /// @dev Authority is set to 0 to keep this as owner only authority
    constructor(
        address _owner,
        address _queue,
        address[] memory defaultPausers
    )
        AccessAuthority(_owner, Authority(address(0)), defaultPausers)
    {
        totalDeprecationSteps = 2;
        queue = _queue;

        _setPublicCapability(queue, OneToOneQueue.processOrders.selector, true);
        _setPublicCapability(queue, OneToOneQueue.submitOrder.selector, true);
        _setPublicCapability(queue, OneToOneQueue.submitOrderAndProcess.selector, true);
    }

    /**
     * @notice override of the canCallVerbose hook to add verbosity for deprecation
     * @dev The following are how each deprecation step's verbose errors are handled:
     * STEP 1:
     *  - Functions are deprecated using setPublicCapability(false) as seen in _onDeprecationContinue.
     *    So return true if function has public capability, and false with deprecation reason if false
     * STEP 2:
     *  - The contract is fully deprecated and should not be callable at all. Include a fully deprecated message
     */
    function _canCallVerboseExtentionHook(
        address user,
        address target,
        bytes calldata data
    )
        internal
        view
        override
        returns (bool, string memory)
    {
        if (deprecationStep == 1) {
            bool publicCapability = isCapabilityPublic[target][bytes4(data[:4])];
            return (publicCapability, "- Deprecation in progress ");
        }
        // Using the step instead of isFullyDeprecated to save a cold storage read.
        if (deprecationStep == 2) {
            return (false, "- Fully Deprecated ");
        }
        return (true, "");
    }

    /// @dev Step 2
    function _onDeprecationContinue(uint8 newStep) internal override {
        if (newStep == 1) {
            setPublicCapability(queue, OneToOneQueue.submitOrder.selector, false);
            setPublicCapability(queue, OneToOneQueue.submitOrderAndProcess.selector, false);
        } else if (newStep == 2) {
            if (OneToOneQueue(queue).totalSupply() != 0) {
                revert QueueNotEmpty();
            }
            _pause();
        }
    }

}
