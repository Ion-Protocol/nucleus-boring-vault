// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import { DecoderCustomTypes } from "src/interfaces/DecoderCustomTypes.sol";

abstract contract SuperBridgeDecoderAndSanitizer is BaseDecoderAndSanitizer {

    // @desc prove a withdrawal transaction to begin a L2->L1 withdrawal
    // @tag sender:address:address of the sender of the transaction
    // @tag target:address:address of the recipient of the transaction
    // @tag data:bytes:data of the transaction
    function proveWithdrawalTransaction(
        DecoderCustomTypes.WithdrawalTransaction memory _tx,
        uint256 _disputeGameIndex,
        DecoderCustomTypes.OutputRootProof calldata _outputRootProof,
        bytes[] calldata _withdrawalProof
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encode(_tx.sender, _tx.target, _tx.data);
    }

    // @desc finalize a withdrawal transaction to complete a L2->L1 withdrawal
    // @tag sender:address:address of the sender of the transaction
    // @tag target:address:address of the recipient of the transaction
    // @tag data:bytes:data of the transaction
    function finalizeWithdrawalTransaction(DecoderCustomTypes.WithdrawalTransaction memory _tx)
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encode(_tx.sender, _tx.target, _tx.data);
    }

    // @desc finalize a withdrawal transaction to complete a L2->L1 withdrawal, with a specified proof submitter
    // @tag sender:address:address of the sender of the transaction
    // @tag target:address:address of the recipient of the transaction
    // @tag data:bytes:data of the transaction
    function finalizeWithdrawalTransactionExternalProof(
        DecoderCustomTypes.WithdrawalTransaction memory _tx,
        address _proofSubmitter
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encode(_tx.sender, _tx.target, _tx.data);
    }

}
