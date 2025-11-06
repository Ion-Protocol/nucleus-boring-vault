// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AccessAuthority, RolesAuthority } from "./abstract/AccessAuthority.sol";
import { OneToOneQueue } from "./OneToOneQueue.sol";
import { Authority } from "@solmate/auth/Auth.sol";

/// NOTE: Format Better
/// @dev 2 deprecation steps
/// 1: Dissable new orders but allow solving existing ones
/// 2: Dissable everything via a pause. But ensure the queue is empty
contract QueueAccessAuthority is AccessAuthority {

    address public queue;
    mapping(address => bool) public isBlacklisted;

    event BlacklistUpdated(address indexed user, bool indexed isBlacklisted);

    error QueueNotEmpty();

    /// @dev owner starts as the msg.sender so that permissioned functions may be called in the constructor, however,
    /// ownership must be transferred to the intended owner afterwards
    constructor(
        address _owner,
        address _queue,
        address[] memory defaultPausers
    )
        /// NOTE: Pass in owner here, but don't set it in parent constructor, have a hook for initRoles, then transfer
        /// here.
        AccessAuthority(msg.sender, defaultPausers)
    {
        queue = _queue;
        setPublicCapability(queue, OneToOneQueue.processOrders.selector, true);
        setPublicCapability(queue, OneToOneQueue.submitOrder.selector, true);
        setPublicCapability(queue, OneToOneQueue.submitOrderAndProcess.selector, true);

        transferOwnership(_owner);
    }

    /// @dev override canCall but add on the blacklist check
    /// NOTE: Remove blacklist
    function canCall(address user, address target, bytes4 functionSig) public view virtual override returns (bool) {
        if (isBlacklisted[user]) {
            return false;
        }
        return super.canCall(user, target, functionSig);
    }

    /// @notice set the blacklist status for users
    function setUsersBlacklistStatus(address[] memory users, bool[] memory isBlacklistedStatus) external requiresAuth {
        for (uint256 i; i < users.length; i++) {
            isBlacklisted[users[i]] = isBlacklistedStatus[i];
            emit BlacklistUpdated(users[i], isBlacklistedStatus[i]);
        }
    }

    /// @dev override getUnauthorizedReasons but add on the blacklist check
    function getUnauthorizedReasons(
        address user,
        bytes4 functionSig
    )
        public
        view
        virtual
        override
        returns (string memory reason)
    {
        reason = super.getUnauthorizedReasons(user, functionSig);
        if (isBlacklisted[user]) {
            reason = string(abi.encodePacked(reason, "- Blacklisted "));
        }
    }

    /// @dev Step 1
    /// NOTE: Remove the "begin" notion
    function _onDeprecationBegin() internal override {
        setPublicCapability(queue, OneToOneQueue.submitOrder.selector, false);
        setPublicCapability(queue, OneToOneQueue.submitOrderAndProcess.selector, false);
    }

    /// @dev Step 2
    function _onDeprecationContinue(uint8 newStep) internal override {
        if (OneToOneQueue(queue).totalSupply() != 0) {
            revert QueueNotEmpty();
        }
        /// NOTE: Instead of having to remember to set this true, have it automatically done once we reach the "size"
        /// which we can set in constructor or something
        isFullyDeprecated = true;
        _pause();
    }

}
