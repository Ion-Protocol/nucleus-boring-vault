// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Auth } from "@solmate/auth/Auth.sol";
import { AccessAuthority } from "src/helper/one-to-one-queue/abstract/AccessAuthority.sol";

/**
 * @title VerboseAuth
 * @notice A verbose version of the solmate Auth contract
 */
abstract contract VerboseAuth is Auth {

    /// NOTE: Remove redundant functionSig
    error Unauthorized(address caller, bytes4 functionSig, bytes data, string reasons);

    modifier requiresAuth() virtual override {
        if (isAuthorized(msg.sender, msg.sig)) {
            _;
        } else {
            revert Unauthorized(
                msg.sender,
                msg.sig,
                msg.data,
                /// NOTE: Instead of msg.sig can pass in msg.data and parse out signature, allows more flexibility
                AccessAuthority(address(authority)).getUnauthorizedReasons(msg.sender, msg.sig)
            );
        }
    }

}
