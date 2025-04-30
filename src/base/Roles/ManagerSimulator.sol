// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import { BoringVault } from "src/base/BoringVault.sol";
import { MerkleProofLib } from "@solmate/utils/MerkleProofLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { BalancerVault } from "src/interfaces/BalancerVault.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { AuthOwnable2Step } from "src/helper/AuthOwnable2Step.sol";

/**
 * @title ManagerWithTokenBalanceVerification
 * @custom:security-contact security@molecularlabs.io
 */
contract ManagerSimulator is AuthOwnable2Step {
    // CONSTANTS
    bytes4 SINGLE_MANAGE_SELECTOR = 0xf6e715d0;

    /// @dev not exactly an error. Errors with data so we can simulate calls and get this data with a dry run
    error ResultingTokenBalancesPostSimulation(address[] tokens, uint256[] tokenBals);

    // ERRORS
    error ManagerSimulator__ErrorGettingTokenBalance(address token, bytes response);
    error ManagerSimulator__ManagementError(address target, bytes targetData, uint256 value, bytes response);
    error ManagerSimulator__TokenHasNoCode(address token);

    // ManageCall struct
    struct ManageCall {
        address target;
        bytes targetData;
        uint256 valueToSend;
    }

    // Native token address signifier
    address public constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor() AuthOwnable2Step(msg.sender, Authority(address(0))) { }

    /**
     * @dev helper function to get an array of token balances including native and reverts with exact token responsible
     * @param boringVault to get token balances of
     * @param tokens to scan for balances
     */
    function tokenBalances(
        BoringVault boringVault,
        address[] calldata tokens
    )
        public
        view
        returns (uint256[] memory tokenBals)
    {
        uint256 length = tokens.length;
        if (length == 0) {
            return tokenBals;
        }

        tokenBals = new uint256[](length);

        for (uint256 i; i < length;) {
            address token = tokens[i];
            if (token == NATIVE) {
                tokenBals[i] = address(boringVault).balance;
            } else {
                if (address(token).code.length == 0) revert ManagerSimulator__TokenHasNoCode(token);

                (bool success, bytes memory response) =
                    token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(boringVault)));

                if (!success) {
                    revert ManagerSimulator__ErrorGettingTokenBalance(token, response);
                }

                tokenBals[i] = abi.decode(response, (uint256));
            }

            unchecked {
                ++i;
            }
        }

        return tokenBals;
    }

    /**
     * @dev function to do token simulation, errors with the simulation data to avoid necessitating a sent transaction
     * @param boringVault to simulate on
     * @param managerCalls to perform
     * @param tokens to retrieve simulations for
     */
    function tokenBalancesSimulation(
        BoringVault boringVault,
        ManageCall[] calldata managerCalls,
        address[] calldata tokens
    )
        public
    {
        _manageVault(boringVault, managerCalls);
        uint256[] memory tokenBals = tokenBalances(boringVault, tokens);

        // Function will always revert
        revert ResultingTokenBalancesPostSimulation(tokens, tokenBals);
    }

    /// NOTE _manageVault calls manage() directly for simplicity, and does not simulate errors with decoders, tree
    /// permissions or micromanagers
    function _manageVault(BoringVault boringVault, ManageCall[] calldata manageCalls) internal requiresAuth {
        // for loop to do execution, if failure error verbose
        uint256 length = manageCalls.length;
        for (uint256 i; i < length;) {
            ManageCall memory call = manageCalls[i];
            (bool success, bytes memory response) = address(boringVault).call(
                abi.encodeWithSelector(SINGLE_MANAGE_SELECTOR, call.target, call.targetData, call.valueToSend)
            );

            if (!success) {
                revert ManagerSimulator__ManagementError(call.target, call.targetData, call.valueToSend, response);
            }
            unchecked {
                ++i;
            }
        }
    }
}
