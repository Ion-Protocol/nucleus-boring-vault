// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import { SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

abstract contract LayerZeroOFTDecoderAndSanitizer is BaseDecoderAndSanitizer {
    error LayerZeroOFTDecoderAndSanitizer_ComposedMsgNotSupported();

    /**
     * @dev _sendParam:
     *     uint32 dstEid; // Destination endpoint ID.                                                              [VERIFY]
     *     bytes32 to; // Recipient address.                                                                       [VERIFY]
     *     uint256 amountLD; // Amount to send in local decimals.
     *     uint256 minAmountLD; // Minimum amount to send in local decimals.
     *     bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
     *     bytes composeMsg; // The composed message for the send() operation.                                     [NONE]
     *     bytes oftCmd; // The OFT command to be executed, unused in default OFT implementations. 0 for Taxi (faster,
     * expensive) 1 for Bus (slower, cheaper)
     * @dev _fee:
     *     uint256 nativeFee;
     *     uint256 lzTokenFee;
     */
    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata,
        address refundReceiver
    )
        external
        view
        returns (bytes memory)
    {
        if (bytes32ToAddress(_sendParam.to) != boringVault || refundReceiver != boringVault) {
            revert NotVault();
        }
        if (_sendParam.composeMsg.length > 0) {
            revert LayerZeroOFTDecoderAndSanitizer_ComposedMsgNotSupported();
        }

        return abi.encodePacked(_sendParam.dstEid);
    }

    function bytes32ToAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }
}
