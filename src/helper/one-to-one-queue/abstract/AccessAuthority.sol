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

    enum REASON {
        NOT_PAUSED,
        PAUSED_BY_PROTOCOL,
        DEPRECATION_IN_PROGRESS,
        DEPRECATED
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    REASON public pauseReason;

    /// @notice Emitted when deprecation process begins
    /// @param step The deprecation step number
    event DeprecationBegun(uint8 step);

    /// @notice Emitted when deprecation continues to next step
    /// @param newStep The new deprecation step
    event DeprecationContinued(uint8 newStep);

    /// @notice Emitted when deprecation is finalized
    /// @param newStep The new deprecation step
    event DeprecationFinished(uint8 newStep);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Current deprecation step (0 = not deprecated)
    uint8 public deprecationStep;

    /// @notice Bool flag if deprecation is complete
    bool public isFullyDeprecated;

    error AccessAuthority__paused(REASON reason, uint8 deprecationStepIfInDeprecation);
    error DeprecationAlreadyBegun(uint8 currentStep);
    error DeprecationNotBegun();

    function pause() external requiresAuth {
        pauseReason = REASON.PAUSED_BY_PROTOCOL;
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

    /// @dev if paused, no functions are now public
    function canCallReason(address user, address target, bytes4 functionSig) public view virtual returns (bool) {
        // if paused, only owner can call
        if (paused()) {
            revert AccessAuthority__paused(pauseReason, deprecationStep);
        }
        return super.canCall(user, target, functionSig);
    }

    /*//////////////////////////////////////////////////////////////
                       INTERNAL HOOK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice helper to pause with the deprecated reason
     */
    function _pauseForDeprecation() internal {
        _pause();
        pauseReason = REASON.DEPRECATED;
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
