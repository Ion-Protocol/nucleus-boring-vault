// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";

/**
 * @title DeprecatableRolesAuthority
 * @notice Abstract contract for managing roles, deprecation at the system level
 */
abstract contract DeprecatableRolesAuthority is Pausable, RolesAuthority {

    REASON public pauseReason;

    function pause() external requiresAuth {
        pauseReason = REASON.PAUSED_BY_PROTOCOL;
        _pause();
    }

    /// @dev if paused, no functions are now public
    function canCall(address user, address target, bytes4 functionSig) public view virtual override returns (bool) {
        // if paused, only owner can call
        if (paused()) {
            if (msg.sender == owner) {
                return true;
            }

            revert DeprecatableRolesAuthority__paused(pauseReason, deprecationStep);
        }
        return super.canCall(user, target, functionSig);
    }

    enum REASON {
        NOT_PAUSED,
        PAUSED_BY_PROTOCOL,
        DEPRECATION_IN_PROGRESS,
        DEPRECATED
    }

    error DeprecatableRolesAuthority__paused(REASON reason, uint8 deprecationStepIfInDeprecation);
    error DeprecationAlreadyBegun(uint8 currentStep);
    error DeprecationNotBegun();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                         DEPRECATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
