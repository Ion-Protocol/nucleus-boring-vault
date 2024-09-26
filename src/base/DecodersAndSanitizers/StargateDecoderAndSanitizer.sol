// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

struct lzTxObj {
    uint256 dstGasForCall;
    uint256 dstNativeAmount;
    bytes dstNativeAddr;
}

contract StargateDecoderAndSanitizer is BaseDecoderAndSanitizer {
    error StargateDecoderAndSanitizer_LzTxParamsNotSupported();
    error StargateDecoderAndSanitizer_PayloadNotSupported();

    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) { }

    /**
     * _dstChainID must verify
     * _srcPoolId must verify
     * _dstPoolId must verify
     * _refundAddress any
     * _amountLD any
     * _minAmountLD any
     * _lzTxParams:
     *     0 additional gasLimit increase
     *     0 airdrop
     *     at 0x address
     * _to must verify
     * _payload must be empty
     */
    function swap(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable,
        uint256,
        uint256,
        lzTxObj memory _lzTxParams,
        bytes calldata _to,
        bytes calldata _payload
    )
        external
        pure
        returns (bytes memory)
    {
        if (_lzTxParams.dstGasForCall > 0 || _lzTxParams.dstNativeAmount > 0 || _lzTxParams.dstNativeAddr.length > 0) {
            revert StargateDecoderAndSanitizer_LzTxParamsNotSupported();
        }
        if (_payload.length > 0) {
            revert StargateDecoderAndSanitizer_PayloadNotSupported();
        }
        return abi.encodePacked(_dstChainId, _srcPoolId, _dstPoolId, _to);
    }
}
