// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {
    BaseDecoderAndSanitizer,
    DecoderCustomTypes
} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract EigenLayerLSTStakingDecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== ERRORS ===============================

    error EigenLayerLSTStakingDecoderAndSanitizer__CanOnlyReceiveAsTokens();

    //============================== EIGEN LAYER ===============================

    // @desc deposit into a strategy on Eigen Layer
    // @tag strategy:address:the address of the strategy
    // @tag token:address:the address of the token
    function depositIntoStrategy(
        address strategy,
        address token,
        uint256
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(strategy, token);
    }

    // @desc queue withdrawals on Eigen Layer
    // @tag strategies:bytes:packed addresses of each strategy address and the withdrawer address in each
    // queuedWithdrawParams
    function queueWithdrawals(DecoderCustomTypes.QueuedWithdrawalParams[] calldata queuedWithdrawalParams)
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        for (uint256 i = 0; i < queuedWithdrawalParams.length; i++) {
            for (uint256 j = 0; j < queuedWithdrawalParams[i].strategies.length; j++) {
                addressesFound = abi.encodePacked(addressesFound, queuedWithdrawalParams[i].strategies[j]);
            }
            addressesFound = abi.encodePacked(addressesFound, queuedWithdrawalParams[i].withdrawer);
        }
    }

    // @desc complete queued withdrawals on Eigen Layer
    // @tag packedArgs:bytes:complicated packed arguments
    function completeQueuedWithdrawals(
        DecoderCustomTypes.Withdrawal[] calldata withdrawals,
        address[][] calldata tokens,
        uint256[] calldata,
        bool[] calldata receiveAsTokens
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        for (uint256 i = 0; i < withdrawals.length; i++) {
            if (!receiveAsTokens[i]) {
                revert EigenLayerLSTStakingDecoderAndSanitizer__CanOnlyReceiveAsTokens();
            }

            addressesFound = abi.encodePacked(
                addressesFound, withdrawals[i].staker, withdrawals[i].delegatedTo, withdrawals[i].withdrawer
            );
            for (uint256 j = 0; j < withdrawals[i].strategies.length; j++) {
                addressesFound = abi.encodePacked(addressesFound, withdrawals[i].strategies[j]);
            }
            for (uint256 j = 0; j < tokens.length; j++) {
                addressesFound = abi.encodePacked(addressesFound, tokens[i][j]);
            }
        }
    }

}
