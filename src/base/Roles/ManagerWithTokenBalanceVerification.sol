// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import { BoringVault } from "src/base/BoringVault.sol";
import { MerkleProofLib } from "@solmate/utils/MerkleProofLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { BalancerVault } from "src/interfaces/BalancerVault.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { AuthOwnable2Step } from "src/helper/AuthOwnable2Step.sol";

/**
 * @title ManagerWithTokenBalanceVerification
 * @custom:security-contact security@molecularlabs.io
 */
contract managerWithTokenBalanceVerification is AuthOwnable2Step {
    error ManagerWithTokenBalanceVerification__InvalidArrayLength();

    BoringVault public immutable boringVault;

    constructor(address _owner, Authority _authority, BoringVault _boringVault) AuthOwnable2Step(_owner, _authority) {
        boringVault = BoringVault(_boringVault);
    }

    function manageVaultWithTokenBalanceVerification(
        address[] calldata targets,
        bytes[] calldata targetData,
        ERC20[] calldata tokensForVerification,
        int256[] calldata allowableTokenDelta
    )
        public
    {
        if (targets.length != targetData.length) revert ManagerWithTokenBalanceVerification__InvalidArrayLength();
        if (tokensForVerification.length != allowableTokenDelta.length) {
            revert ManagerWithTokenBalanceVerification__InvalidArrayLength();
        }

        // use token bal now to get the balances before

        // for loop to do execution, if failure exti verbose and return token balances then

        // if success, fetch token balances after

        // check token deltas
    }

    function tokenBalNow(ERC20[] calldata tokens) public view returns (uint256[] memory tokenBalsNow) {
        new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenBalsNow[i] = tokens[i].balanceOf(address(boringVault));
        }
        return tokenBalsNow;
    }
}
