// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AccessAuthority, RolesAuthority } from "./abstract/AccessAuthority.sol";
import { OneToOneQueue } from "./OneToOneQueue.sol";
import { Authority } from "@solmate/auth/Auth.sol";

contract QueueAccessAuthority is AccessAuthority {

    /// @dev 2 deprecation steps
    /// 1: Dissable new orders but allow solving existing ones
    /// 2: Dissable everything via a pause. But ensure the queue is empty
    enum DEPRECATION_STEP {
        NOT_DEPRECATED,
        NO_NEW_ORDERS,
        CLOSED
    }

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
        AccessAuthority(msg.sender, defaultPausers)
    {
        queue = _queue;
        setPublicCapability(queue, OneToOneQueue.processOrders.selector, true);
        setPublicCapability(queue, OneToOneQueue.submitOrder.selector, true);
        setPublicCapability(queue, OneToOneQueue.submitOrderAndProcess.selector, true);

        transferOwnership(_owner);
    }

    /// @dev override canCall but add on the blacklist check
    function canCall(address user, address target, bytes4 functionSig) public view virtual override returns (bool) {
        if (isBlacklisted[user]) {
            return false;
        }
        return super.canCall(user, target, functionSig);
    }

    /// @notice set the blacklist status for users
    function setUsersBlacklistStatus(
        address[] memory users,
        bool[] memory isBlacklistedStatus
    )
        external
        requiresAuth
    {
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
    function _onDeprecationBegin() internal override {
        setPublicCapability(queue, OneToOneQueue.submitOrder.selector, false);
        setPublicCapability(queue, OneToOneQueue.submitOrderAndProcess.selector, false);
    }

    /// @dev Step 2
    function _onDeprecationContinue(uint8 newStep) internal override {
        if (OneToOneQueue(queue).totalSupply() != 0) {
            revert QueueNotEmpty();
        }
        isFullyDeprecated = true;
        _pause();
    }

}
