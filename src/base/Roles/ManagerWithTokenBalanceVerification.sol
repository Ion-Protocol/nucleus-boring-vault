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
contract ManagerWithTokenBalanceVerification is AuthOwnable2Step {
    // CONSTANTS
    bytes4 SINGLE_MANAGE_SELECTOR = 0xf6e715d0;

    /// @dev not really an error. Errors with data so we can simulate calls and get this data with a dry run
    error TokenBalancesNow(address[] tokens, uint256[] tokenBals);

    // ERRORS
    error ManagerWithTokenBalanceVerification__InvalidArrayLength();
    error ManagerWithTokenBalanceVerification__ErrorGettingTokenBalance(address token);
    error ManagerWithTokenBalanceVerification__ManagementError(
        address target, bytes targetData, uint256 value, bytes response
    );
    error ManagerWithTokenBalanceVerification__TokenDeltaViolation(
        address token, uint256 balanceBefore, uint256 balanceAfter, int256 balanceDelta, int256 allowedBalanceDelta
    );
    error ManagerWithTokenBalanceVerification__TokenHasNoCode(address token);

    // EVENTS
    event ManagerWithTokenBalanceVerification__TokenBalancesAfterExecutionButBeforeFailure(
        address[] tokens, uint256[] balances
    );
    event ManagerWithTokenBalanceVerification__TokenBalancesBeforeExecution(address[] tokens, uint256[] balances);
    event ManagerWithTokenBalanceVerification__TokenBalancesAfterSuccessfulExecution(
        address[] tokens, uint256[] balances
    );

    event ManagerWithTokenBalanceVerification__ChangesAfterExecutionButBeforeFailure(
        address[] tokens, int256[] changes
    );
    event ManagerWithTokenBalanceVerification__TokenChangesAfterSuccessfulExecution(address[] tokens, int256[] changes);

    // ManageCall struct
    // makes calls more efficient with packing
    struct ManageCall {
        address target;
        bytes targetData;
        uint256 valueToSend;
    }

    // native token address signifier
    address public constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor() AuthOwnable2Step(msg.sender, Authority(address(0))) { }

    function manageVaultWithTokenBalanceVerification(
        BoringVault boringVault,
        ManageCall[] calldata manageCalls,
        address[] calldata tokensForVerification,
        int256[] calldata allowableTokenDelta
    )
        external
        requiresAuth
        returns (uint256[] memory tokenBalsAfter, int256[] memory tokenDeltas)
    {
        // check array lengths
        if (tokensForVerification.length != allowableTokenDelta.length || tokensForVerification.length == 0) {
            revert ManagerWithTokenBalanceVerification__InvalidArrayLength();
        }

        // get balances before execution
        uint256[] memory tokenBalsBefore = tokenBalances(boringVault, tokensForVerification);
        // emit the token balances
        emit ManagerWithTokenBalanceVerification__TokenBalancesBeforeExecution(tokensForVerification, tokenBalsBefore);

        // for loop to do execution, if failure error verbose and return token balances then
        uint256 length = manageCalls.length;
        for (uint256 i; i < length;) {
            ManageCall memory call = manageCalls[i];
            (bool success, bytes memory response) = address(boringVault).call(
                abi.encodeWithSelector(SINGLE_MANAGE_SELECTOR, call.target, call.targetData, call.valueToSend)
            );

            if (!success) {
                // verbose enough?
                // could:
                // EMIT this info as event
                // attempt tx again through interface to get more verbose stack trace error?
                // revert in case for some reason a second attempt to call passes

                // get the new token balances after previous txs
                tokenBalsAfter = tokenBalances(boringVault, tokensForVerification);
                // get the token deltas
                tokenDeltas = _getTokenDeltas(tokensForVerification, tokenBalsBefore, tokenBalsAfter);
                // emit the data
                emit ManagerWithTokenBalanceVerification__TokenBalancesAfterExecutionButBeforeFailure(
                    tokensForVerification, tokenBalsAfter
                );
                emit ManagerWithTokenBalanceVerification__ChangesAfterExecutionButBeforeFailure(
                    tokensForVerification, tokenDeltas
                );
                // revert with a verbose error message
                revert ManagerWithTokenBalanceVerification__ManagementError(
                    call.target, call.targetData, call.valueToSend, response
                );
            }
            unchecked {
                ++i;
            }
        }

        // get token changes
        tokenBalsAfter = tokenBalances(boringVault, tokensForVerification);
        tokenDeltas = _getTokenDeltas(tokensForVerification, tokenBalsBefore, tokenBalsAfter);

        // emit the token balance and change data before checking them
        emit ManagerWithTokenBalanceVerification__TokenBalancesAfterSuccessfulExecution(
            tokensForVerification, tokenBalsAfter
        );
        emit ManagerWithTokenBalanceVerification__TokenChangesAfterSuccessfulExecution(
            tokensForVerification, tokenDeltas
        );

        // check each token's delta bounds
        for (uint256 i; i < tokenBalsAfter.length;) {
            if (tokenDeltas[i] < allowableTokenDelta[i]) {
                revert ManagerWithTokenBalanceVerification__TokenDeltaViolation(
                    tokensForVerification[i],
                    tokenBalsBefore[i],
                    tokenBalsAfter[i],
                    tokenDeltas[i],
                    allowableTokenDelta[i]
                );
            }
            unchecked {
                ++i;
            }
        }
    }

    function manageVaultWithTokenBalanceVerification(
        BoringVault boringVault,
        ManageCall[] calldata manageCalls
    )
        public
        requiresAuth
    {
        // for loop to do execution, if failure error verbose
        uint256 length = manageCalls.length;
        for (uint256 i; i < length;) {
            ManageCall memory call = manageCalls[i];
            (bool success, bytes memory response) = address(boringVault).call(
                abi.encodeWithSelector(SINGLE_MANAGE_SELECTOR, call.target, call.targetData, call.valueToSend)
            );

            if (!success) {
                revert ManagerWithTokenBalanceVerification__ManagementError(
                    call.target, call.targetData, call.valueToSend, response
                );
            }
            unchecked {
                ++i;
            }
        }
    }

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
                if (address(token).code.length == 0) revert ManagerWithTokenBalanceVerification__TokenHasNoCode(token);

                (bool success, bytes memory response) =
                    token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(boringVault)));

                if (!success) {
                    revert ManagerWithTokenBalanceVerification__ErrorGettingTokenBalance(token);
                }

                tokenBals[i] = abi.decode(response, (uint256));
            }

            unchecked {
                ++i;
            }
        }

        return tokenBals;
    }

    function tokenBalancesNow(
        BoringVault boringVault,
        ManageCall[] calldata managerCalls,
        address[] calldata tokens
    )
        public
    {
        manageVaultWithTokenBalanceVerification(boringVault, managerCalls);
        uint256[] memory tokenBals = tokenBalances(boringVault, tokens);
        revert TokenBalancesNow(tokens, tokenBals);
    }

    function _getTokenDeltas(
        address[] calldata tokens,
        uint256[] memory startingBalances,
        uint256[] memory endingBalances
    )
        internal
        pure
        returns (int256[] memory tokenDeltas)
    {
        uint256 length = tokens.length;
        tokenDeltas = new int256[](length);

        // get each tokens changes
        for (uint256 i; i < length;) {
            tokenDeltas[i] = int256(endingBalances[i]) - int256(startingBalances[i]);

            unchecked {
                ++i;
            }
        }
    }
}
