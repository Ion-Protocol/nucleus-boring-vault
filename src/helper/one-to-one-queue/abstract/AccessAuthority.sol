// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";

/**
 * @title AccessAuthority
 * @notice Abstract contract for managing access to all of a system's external functions. Examples include:
 * pausing
 * roles/ownership
 * deprecation
 * whitelist/blacklist
 */
abstract contract AccessAuthority is Pausable, RolesAuthority {

    error Unauthorized(address caller, address target, bytes4 functionSig);
    error DeprecationNotBegun();
    error DeprecationAlreadyBegun(uint8 currentStep);

    /// @notice Emitted when deprecation process begins
    /// @param step The deprecation step number
    event DeprecationBegun(uint8 step);

    /// @notice Emitted when deprecation continues to next step
    /// @param newStep The new deprecation step
    event DeprecationContinued(uint8 newStep);

    /// @notice Emitted when deprecation is finalized
    /// @param newStep The new deprecation step
    event DeprecationFinished(uint8 newStep);

    /// @notice Current deprecation step (0 = not deprecated)
    uint8 public deprecationStep;

    /// @notice Bool flag if deprecation is complete
    bool public isFullyDeprecated;

    // TODO: order functions here according to style guide
    modifier requiresAuth() virtual override {
        if (isAuthorized(msg.sender, msg.sig)) {
            _;
        } else {
            revert Unauthorized(msg.sender, address(this), msg.sig);
        }
    }

    function canCall(address user, address target, bytes4 functionSig) public view virtual override returns (bool) {
        // If the contract is paused cannot call anything, otherwise follow rules set by the RolesAuthority
        if (paused()) {
            return false;
        }
        return super.canCall(user, target, functionSig);
    }

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

    function pause() external requiresAuth {
        _pause();
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
