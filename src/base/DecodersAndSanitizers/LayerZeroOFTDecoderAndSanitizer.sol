// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import { SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

contract LayerZeroOFTDecoderAndSanitizer is BaseDecoderAndSanitizer {
    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) { }

    /*
    _sendParam:
    uint32 dstEid; // Destination endpoint ID.                                                              [VERIFY]
    bytes32 to; // Recipient address.                                                                       [VERIFY]
        uint256 amountLD; // Amount to send in local decimals.
        uint256 minAmountLD; // Minimum amount to send in local decimals.
        bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
        bytes composeMsg; // The composed message for the send() operation.
        bytes oftCmd; // The OFT command to be executed, unused in default OFT implementations.
    _fee:
        uint256 nativeFee;
        uint256 lzTokenFee;
    */
    function send(SendParam calldata _sendParam, MessagingFee calldata, address) external pure returns (bytes memory) {
        return abi.encodePacked(_sendParam.dstEid, _sendParam.to);
    }
}
