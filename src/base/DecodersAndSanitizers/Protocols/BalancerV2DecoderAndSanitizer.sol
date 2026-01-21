// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {
    BaseDecoderAndSanitizer,
    DecoderCustomTypes
} from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

abstract contract BalancerV2DecoderAndSanitizer is BaseDecoderAndSanitizer {

    //============================== ERRORS ===============================

    error BalancerV2DecoderAndSanitizer__SingleSwapUserDataLengthNonZero();
    error BalancerV2DecoderAndSanitizer__InternalBalancesNotSupported();

    //============================== BALANCER V2 ===============================

    // @desc Flash loan from the Balancer V2 protocol
    // @tag recipient:address:the address of the recipient
    // @tag tokens:bytes:packed bytes of every token in each address[] tokens input.
    function flashLoan(
        address recipient,
        address[] calldata tokens,
        uint256[] calldata,
        bytes calldata
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(recipient);
        for (uint256 i; i < tokens.length; ++i) {
            addressesFound = abi.encodePacked(addressesFound, tokens[i]);
        }
    }

    // @desc Swap tokens in the Balancer V2 protocol. Reverts if userData is not empty or if internal balances are used
    // @tag pool:address:the address of the pool
    // @tag assetIn:address:the address of the input asset
    // @tag assetOut:address:the address of the output asset
    // @tag sender:address:the address of the sender
    // @tag recipient:address:the address of the recipient
    function swap(
        DecoderCustomTypes.SingleSwap calldata singleSwap,
        DecoderCustomTypes.FundManagement calldata funds,
        uint256,
        uint256
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        // Sanitize raw data
        if (singleSwap.userData.length > 0) revert BalancerV2DecoderAndSanitizer__SingleSwapUserDataLengthNonZero();
        if (funds.fromInternalBalance) revert BalancerV2DecoderAndSanitizer__InternalBalancesNotSupported();
        if (funds.toInternalBalance) revert BalancerV2DecoderAndSanitizer__InternalBalancesNotSupported();

        // Return addresses found
        addressesFound = abi.encodePacked(
            _getPoolAddressFromPoolId(singleSwap.poolId),
            singleSwap.assetIn,
            singleSwap.assetOut,
            funds.sender,
            funds.recipient
        );
    }

    // @desc Join a pool in the Balancer V2 protocol, will revert if internal balances are used
    // @tag pool:address:the address of the pool
    // @tag sender:address:the address of the sender
    // @tag recipient:address:the address of the recipient
    // @tag assets:bytes:packed bytes of every address in the req.assets input.
    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        DecoderCustomTypes.JoinPoolRequest calldata req
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        // Sanitize raw data
        if (req.fromInternalBalance) revert BalancerV2DecoderAndSanitizer__InternalBalancesNotSupported();
        // Return addresses found
        addressesFound = abi.encodePacked(_getPoolAddressFromPoolId(poolId), sender, recipient);
        uint256 assetsLength = req.assets.length;
        for (uint256 i; i < assetsLength; ++i) {
            addressesFound = abi.encodePacked(addressesFound, req.assets[i]);
        }
    }

    // @desc Exit a pool in the Balancer V2 protocol, will revert if internal balances are used
    // @tag pool:address:the address of the pool
    // @tag sender:address:the address of the sender
    // @tag recipient:address:the address of the recipient
    // @tag assets:bytes:packed bytes of every address in the req.assets input.
    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        DecoderCustomTypes.ExitPoolRequest calldata req
    )
        external
        pure
        virtual
        returns (bytes memory addressesFound)
    {
        // Sanitize raw data
        if (req.toInternalBalance) revert BalancerV2DecoderAndSanitizer__InternalBalancesNotSupported();
        // Return addresses found
        addressesFound = abi.encodePacked(_getPoolAddressFromPoolId(poolId), sender, recipient);
        uint256 assetsLength = req.assets.length;
        for (uint256 i; i < assetsLength; ++i) {
            addressesFound = abi.encodePacked(addressesFound, req.assets[i]);
        }
    }

    // @desc Deposit into the Balancer V2 protocol
    // @tag recipient:address:the address of the recipient
    function deposit(uint256, address recipient) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(recipient);
    }

    // @desc Withdraw from the Balancer V2 protocol to msg.sender
    function withdraw(uint256) external pure virtual returns (bytes memory addressesFound) {
        // No addresses in data
        return addressesFound;
    }

    function mint(address gauge) external pure virtual returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(gauge);
    }

    // ========================================= INTERNAL HELPER FUNCTIONS =========================================

    /**
     * @notice Internal helper function that converts poolIds to pool addresses.
     */
    function _getPoolAddressFromPoolId(bytes32 poolId) internal pure returns (address) {
        return address(uint160(uint256(poolId >> 96)));
    }

}
