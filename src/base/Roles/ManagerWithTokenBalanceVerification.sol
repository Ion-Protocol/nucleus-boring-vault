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
import { ManagerSimulator } from "src/base/Roles/ManagerSimulator.sol";

/**
 * @title ManagerWithTokenBalanceVerification
 * @custom:security-contact security@molecularlabs.io
 */
contract ManagerWithTokenBalanceVerification is ManagerSimulator, AuthOwnable2Step {
    // ERRORS
    error ManagerWithTokenBalanceVerification__InvalidArrayLength();
    error ManagerWithTokenBalanceVerification__TokenDeltaViolation(
        address token, uint256 balanceBefore, uint256 balanceAfter, int256 balanceDelta, int256 allowedBalanceDelta
    );

    // EVENTS
    event ManagerWithTokenBalanceVerification__TokenBalancesBeforeExecution(address[] tokens, uint256[] balances);
    event ManagerWithTokenBalanceVerification__TokenBalancesAfterSuccessfulExecution(
        address[] tokens, uint256[] balances
    );

    event ManagerWithTokenBalanceVerification__TokenChangesAfterSuccessfulExecution(address[] tokens, int256[] changes);

    constructor(
        uint8 _nativeTokenDecimals,
        address _owner
    )
        ManagerSimulator(_nativeTokenDecimals)
        AuthOwnable2Step(_owner, Authority(address(0)))
    { }

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

        _manageVault(boringVault, manageCalls);

        // get token changes
        tokenBalsAfter = tokenBalances(boringVault, tokensForVerification);
        tokenDeltas = _getTokenDeltas(tokenBalsBefore, tokenBalsAfter);

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

    function manageVaultWithNoVerification(
        BoringVault boringVault,
        ManageCall[] calldata manageCalls
    )
        public
        requiresAuth
    {
        _manageVault(boringVault, manageCalls);
    }

    function _getTokenDeltas(
        uint256[] memory startingBalances,
        uint256[] memory endingBalances
    )
        internal
        pure
        returns (int256[] memory tokenDeltas)
    {
        uint256 length = startingBalances.length;
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
