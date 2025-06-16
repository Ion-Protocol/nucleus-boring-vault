// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.21;

/**
 * @title HLSpot
 * @custom:security-contact security@molecularlabs.io
 */
abstract contract HLSpot {
    /**
     * @notice Address in slot0 that can be modified.
     */
    address public deployerAddress;
}
