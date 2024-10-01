// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import { MessagingFee, OFTReceipt, SendParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

contract StargateV2DecoderAndSanitizer is BaseDecoderAndSanitizer {
    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) { }

    error StargateV2DecoderAndSanitizer_ComposedMsgNotSupported();

    /**
     * @dev _sendParam:
     *     uint32 dstEid; // Destination endpoint ID.                                                              [VERIFY]
     *     bytes32 to; // Recipient address.                                                                       [VERIFY]
     *     uint256 amountLD; // Amount to send in local decimals.
     *     uint256 minAmountLD; // Minimum amount to send in local decimals.
     *     bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
     *     bytes composeMsg; // The composed message for the send() operation.                                     [NONE]
     *     bytes oftCmd; // The OFT command to be executed, unused in default OFT implementations.                 [NONE]
     * @dev _fee:
     *     uint256 nativeFee;
     *     uint256 lzTokenFee;
     */
    function sendToken(
        SendParam memory _sendParam,
        MessagingFee memory _messagingFee,
        address _refundAddress
    )
        external
        returns (bytes memory)
    {
        if (_sendParam.composeMsg.length > 0) {
            revert StargateV2DecoderAndSanitizer_ComposedMsgNotSupported();
        }
        return abi.encodePacked(_sendParam.dstEid, _sendParam.to, _refundAddress);
    }
}
