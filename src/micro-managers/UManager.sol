// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { AuthOwnable2Step } from "src/helper/AuthOwnable2Step.sol";

abstract contract UManager is AuthOwnable2Step {
    using FixedPointMathLib for uint256;

    // ========================================= STATE =========================================

    /**
     * @notice The period in seconds for the rate limit.
     */
    uint16 public period;

    /**
     * @notice The number of calls allowed per period.
     */
    uint16 public allowedCallsPerPeriod;

    /**
     * @notice The number of calls made in the current period.
     */
    mapping(uint256 => uint256) public callCountPerPeriod;

    //============================== ERRORS ===============================

    error UManager__CallCountExceeded();

    //============================== EVENTS ===============================

    event PeriodUpdated(uint16 oldPeriod, uint16 newPeriod);
    event AllowedCallsPeriodUpdated(uint16 oldAllowance, uint16 newAllowance);

    //============================== MODIFIERS ===============================

    modifier enforceRateLimit() {
        // Use parenthesis to avoid stack too deep error.
        {
            // We include this call in the current call count for period.
            uint256 currentCallCountForPeriod = callCountPerPeriod[block.timestamp % period] + 1;
            if (currentCallCountForPeriod > allowedCallsPerPeriod) {
                revert UManager__CallCountExceeded();
            }
            callCountPerPeriod[block.timestamp % period] = currentCallCountForPeriod;
        }
        _;
    }

    //============================== IMMUTABLES ===============================

    /**
     * @notice The ManagerWithMerkleVerification this uManager works with.
     */
    ManagerWithMerkleVerification internal immutable manager;

    /**
     * @notice The BoringVault this uManager works with.
     */
    address internal immutable boringVault;

    constructor(
        address _owner,
        address _manager,
        address _boringVault
    )
        AuthOwnable2Step(_owner, Authority(address(0)))
    {
        manager = ManagerWithMerkleVerification(_manager);
        boringVault = _boringVault;
    }

    // ========================================= ADMIN FUNCTIONS =========================================

    /**
     * @notice Sets the duration of the period.
     * @dev Callable by MULTISIG_ROLE.
     */
    function setPeriod(uint16 _period) external requiresAuth {
        emit PeriodUpdated(period, _period);
        period = _period;
    }

    /**
     * @notice Sets the number of calls allowed per period.
     * @dev Callable by MULTISIG_ROLE.
     */
    function setAllowedCallsPerPeriod(uint16 _allowedCallsPerPeriod) external requiresAuth {
        emit AllowedCallsPeriodUpdated(allowedCallsPerPeriod, _allowedCallsPerPeriod);
        allowedCallsPerPeriod = _allowedCallsPerPeriod;
    }

    /**
     * @notice Allows auth to set token approvals to zero.
     * @dev Callable by STRATEGIST_ROLE.
     */
    function revokeTokenApproval(
        bytes32[][] calldata manageProofs,
        address[] calldata decodersAndSanitizers,
        ERC20[] calldata tokens,
        address[] calldata spenders
    )
        external
        requiresAuth
    {
        uint256 tokensLength = tokens.length;
        address[] memory targets = new address[](tokensLength);
        bytes[] memory targetData = new bytes[](tokensLength);
        uint256[] memory values = new uint256[](tokensLength);

        for (uint256 i; i < tokensLength; ++i) {
            targets[i] = address(tokens[i]);
            targetData[i] = abi.encodeWithSelector(ERC20.approve.selector, spenders[i], 0);
            // values[i] = 0;
        }

        // Make the manage call.
        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
    }
}
