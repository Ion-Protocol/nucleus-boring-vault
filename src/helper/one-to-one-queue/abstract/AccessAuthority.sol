// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";

/**
 * @title AccessAuthority
 * @notice Abstract contract for managing access to all of a system's external functions. Examples include:
 * pausing
 * roles/ownership
 * deprecation
 * whitelist/blacklist
 */
abstract contract AccessAuthority is Pausable, RolesAuthority {

    /// @notice Current deprecation step (0 = not deprecated)
    uint8 public deprecationStep;

    /// @notice Bool flag if deprecation is complete
    bool public isFullyDeprecated;

    /// @notice mapping of accepted pausers
    mapping(address => bool) public pausers;

    event DeprecationBegun(uint8 step);
    event DeprecationContinued(uint8 newStep);
    event DeprecationFinished(uint8 newStep);
    event PauserStatusSet(address pauser, bool canPause);

    error Unauthorized(address caller, address target, bytes4 functionSig);
    error DeprecationNotBegun();
    error DeprecationAlreadyBegun(uint8 currentStep);

    constructor(address owner, address[] memory defaultPausers) RolesAuthority(owner, Authority(address(0))) {
        uint256 length = defaultPausers.length;
        for (uint256 i; i < length; ++i) {
            pausers[defaultPausers[i]] = true;
            emit PauserStatusSet(defaultPausers[i], true);
        }
    }

    /// @dev requiresAuth is used in this contract and is overriden to match the VerboseAuth signature
    modifier requiresAuth() virtual override {
        if (isAuthorized(msg.sender, msg.sig)) {
            _;
        } else {
            revert Unauthorized(msg.sender, address(this), msg.sig);
        }
    }

    /// @notice only OWNER can set new pauser status
    function setPauserStatus(address pauser, bool canPause) external requiresAuth {
        pausers[pauser] = canPause;
        emit PauserStatusSet(pauser, canPause);
    }

    /// @notice only pausers and OWNER can pause
    function pause() external {
        if (!pausers[msg.sender] && msg.sender != owner) revert Unauthorized(msg.sender, address(this), msg.sig);
        _pause();
    }

    /// @notice only OWNER can unpause
    function unpause() external requiresAuth {
        _unpause();
    }

    /**
     * @notice Begin the deprecation process
     * @dev Sets deprecation step from 0 to 1 and executes step-specific logic
     */
    function beginDeprecation() external virtual requiresAuth {
        if (deprecationStep != 0) revert DeprecationAlreadyBegun(deprecationStep);

        deprecationStep = 1;
        _onDeprecationBegin();

        emit DeprecationBegun(1);
    }

    /**
     * @notice Continue deprecation to next step
     * @dev Advances from current non-zero step to step + 1
     */
    function continueDeprecation() external virtual requiresAuth whenNotPaused {
        if (deprecationStep == 0) revert DeprecationNotBegun();

        ++deprecationStep;
        _onDeprecationContinue(deprecationStep);

        emit DeprecationContinued(deprecationStep);
        if (isFullyDeprecated) {
            emit DeprecationFinished(deprecationStep);
        }
    }

    /// @dev canCall is overriden to add more logic to the requiresAuth modifier
    /// The default extension is that pausing deactivates all functions.
    /// You may also override to check more complex logic for example a whitelist.
    /// It's worth noting that OWNER bypasses this canCall check.
    function canCall(address user, address target, bytes4 functionSig) public view virtual override returns (bool) {
        // If the contract is paused cannot call anything, otherwise follow rules set by the RolesAuthority
        if (paused()) {
            return false;
        }
        return super.canCall(user, target, functionSig);
    }

    /// @dev a new function to get the reason for a failed "canCall" check as a string.
    function getUnauthorizedReasons(address user, bytes4 functionSig)
        public
        view
        virtual
        returns (string memory reason)
    {
        if (paused()) {
            reason = "- Paused ";
        }
        if (isFullyDeprecated) {
            reason = string(abi.encodePacked(reason, "- Fully Deprecated "));
        } else if (deprecationStep > 0) {
            reason = string(abi.encodePacked(reason, "- Deprecation in progress "));
        }

        return reason;
    }

    /**
     * @notice Hook called when deprecation begins
     * @dev Override to implement step 1 specific logic
     */
    function _onDeprecationBegin() internal virtual { }

    /**
     * @notice Hook called when deprecation continues to next step
     * @param newStep The new deprecation step
     * @dev Override to implement step-specific logic
     */
    function _onDeprecationContinue(uint8 newStep) internal virtual { }

}
