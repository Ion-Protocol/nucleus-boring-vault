// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Pausable } from "./Pausable.sol";
import { VerboseAuth, Authority } from "./VerboseAuth.sol";

/**
 * @title AccessAuthority
 * @notice Abstract contract for managing access to all of a system's external functions. Examples include:
 * pausing
 * roles/ownership
 * deprecation
 * whitelist/blacklist
 * @author Based on Solmate
 * (https://github.com/transmissions11/solmate/blob/main/src/auth/authorities/RolesAuthority.sol)
 * @dev This contract is almost identical to RolesAuhtority but features more verbose error messages and some helpers
 * for capability setting without role checks internally.
 */
abstract contract AccessAuthority is Pausable, VerboseAuth, Authority {

    /// @notice Total number of deprecation steps
    uint8 public immutable totalDeprecationSteps;

    /// @notice Current deprecation step (0 = not deprecated)
    uint8 public deprecationStep;

    /// @notice Bool flag if deprecation is complete
    bool public isFullyDeprecated;

    /// @notice Mapping of accepted pausers
    /// @dev We implement this instead of using Roles to eleminate the need for an AccessAuthority for your
    /// AccessAuthority
    mapping(address => bool) public pausers;

    mapping(address => bytes32) public getUserRoles;

    mapping(address => mapping(bytes4 => bool)) public isCapabilityPublic;

    mapping(address => mapping(bytes4 => bytes32)) public getRolesWithCapability;

    event DeprecationBegun(uint8 step);
    event DeprecationContinued(uint8 newStep);
    event DeprecationFinished(uint8 newStep);
    event PauserStatusSet(address pauser, bool canPause);
    event UserRoleUpdated(address indexed user, uint8 indexed role, bool enabled);
    event PublicCapabilityUpdated(address indexed target, bytes4 indexed functionSig, bool enabled);
    event RoleCapabilityUpdated(uint8 indexed role, address indexed target, bytes4 indexed functionSig, bool enabled);

    error DeprecationComplete();

    constructor(
        address _owner,
        Authority _authority,
        address[] memory _defaultPausers
    )
        VerboseAuth(_owner, _authority)
    {
        uint256 length = _defaultPausers.length;
        for (uint256 i; i < length; ++i) {
            pausers[_defaultPausers[i]] = true;
            emit PauserStatusSet(_defaultPausers[i], true);
        }
    }

    /// @notice only OWNER can set new pauser status
    function setPauserStatus(address pauser, bool canPause) external requiresAuthVerbose {
        pausers[pauser] = canPause;
        emit PauserStatusSet(pauser, canPause);
    }

    /// @notice only pausers and OWNER can pause
    function pause() external {
        if (!pausers[msg.sender] && msg.sender != owner) {
            revert VerboseAuth.Unauthorized(msg.sender, msg.data, "- Not a pauser or owner ");
        }
        _pause();
    }

    /// @notice only OWNER can unpause
    function unpause() external requiresAuthVerbose {
        _unpause();
    }

    function setPublicCapability(address target, bytes4 functionSig, bool enabled) public virtual requiresAuthVerbose {
        _setPublicCapability(target, functionSig, enabled);
    }

    function setRoleCapability(
        uint8 role,
        address target,
        bytes4 functionSig,
        bool enabled
    )
        public
        virtual
        requiresAuthVerbose
    {
        _setRoleCapability(role, target, functionSig, enabled);
    }

    function setUserRole(address user, uint8 role, bool enabled) public virtual requiresAuthVerbose {
        if (enabled) {
            getUserRoles[user] |= bytes32(1 << role);
        } else {
            getUserRoles[user] &= ~bytes32(1 << role);
        }

        emit UserRoleUpdated(user, role, enabled);
    }

    /**
     * @notice Continue deprecation to next step
     * @dev Advances from current non-zero step to step + 1
     */
    function continueDeprecation() external virtual requiresAuthVerbose whenNotPaused {
        if (deprecationStep == totalDeprecationSteps) revert DeprecationComplete();

        unchecked {
            ++deprecationStep;
        }
        _onDeprecationContinue(deprecationStep);
        emit DeprecationContinued(deprecationStep);
        if (deprecationStep == totalDeprecationSteps) {
            isFullyDeprecated = true;
            emit DeprecationFinished(deprecationStep);
        }
    }

    /**
     * @dev Verbose version of canCall. Provides detailed reasons for a calls failure with strings.
     * Overriding the hook in this function allows you to include more logic such as a whitelist.
     */
    function canCallVerbose(
        address user,
        address target,
        bytes calldata data
    )
        public
        view
        virtual
        returns (bool canCall, string memory reasons)
    {
        // If the contract is paused cannot call anything, otherwise follow rules set by the original RolesAuthority
        if (paused()) {
            reasons = "- Paused ";
            // canCall is false by default
        } else {
            canCall = true;
        }

        // After the pause check, if canCall remains false, it should always remain false
        bytes4 functionSig = bytes4(data[:4]);
        if (!(isCapabilityPublic[target][functionSig]
                    || bytes32(0) != getUserRoles[user] & getRolesWithCapability[target][functionSig])) {
            canCall = false;
            reasons = string(abi.encodePacked(reasons, "- Unauthorized "));
        }

        (bool canCallExtentions, string memory reasonsExtentions) = _canCallVerboseExtentionHook(user, target, data);

        // The extention may not set canCall true if it is currently false to override the pause or role checks. The
        // extention may only add more strict checks.
        canCall = canCall && canCallExtentions;
        reasons = string(abi.encodePacked(reasons, reasonsExtentions));
    }

    function doesUserHaveRole(address user, uint8 role) public view virtual returns (bool) {
        return (uint256(getUserRoles[user]) >> role) & 1 != 0;
    }

    function doesRoleHaveCapability(uint8 role, address target, bytes4 functionSig) public view virtual returns (bool) {
        return (uint256(getRolesWithCapability[target][functionSig]) >> role) & 1 != 0;
    }

    /**
     * @dev Hook to allow for additional logic to be added to the canCallVerbose function.
     * Additional logic may only add more strict checks to the canCallVerbose function and cannot override a check
     * failing due to a pause or invalid role.
     * Returns true now to enforce only the pause and role checks.
     */
    function _canCallVerboseExtentionHook(
        address user,
        address target,
        bytes calldata data
    )
        internal
        view
        virtual
        returns (bool canCall, string memory reasons)
    {
        canCall = true;
    }

    /**
     * @dev Internal and no-auth version of setPublicCapability
     */
    function _setPublicCapability(address target, bytes4 functionSig, bool enabled) internal virtual {
        isCapabilityPublic[target][functionSig] = enabled;

        emit PublicCapabilityUpdated(target, functionSig, enabled);
    }

    /**
     * @dev Internal and no-auth version of setRoleCapability
     */
    function _setRoleCapability(uint8 role, address target, bytes4 functionSig, bool enabled) internal virtual {
        if (enabled) {
            getRolesWithCapability[target][functionSig] |= bytes32(1 << role);
        } else {
            getRolesWithCapability[target][functionSig] &= ~bytes32(1 << role);
        }

        emit RoleCapabilityUpdated(role, target, functionSig, enabled);
    }

    /**
     * @notice Hook called when deprecation continues to next step
     * @param newStep The new deprecation step
     * @dev Override to implement step-specific logic
     */
    function _onDeprecationContinue(uint8 newStep) internal virtual;

}
