// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// @dev Import the 'MessagingFee' and 'MessagingReceipt' so it's exposed to OApp implementers
// solhint-disable-next-line no-unused-import
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
// @dev Import the 'Origin' so it's exposed to OApp implementers
// solhint-disable-next-line no-unused-import
import { Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppReceiver.sol";

import { OAppAuthCore } from "./OAppAuthCore.sol";
import { OAppAuthReceiver } from "./OAppAuthReceiver.sol";
import { OAppAuthSender } from "./OAppAuthSender.sol";

/**
 * @title OAppAuth
 * @dev Abstract contract serving as the base for OApp implementation, combining OAppSender and OAppReceiver
 * functionality.
 *
 * @dev This Auth version of OAppCore uses solmate's Auth instead of OZ's Ownable for compatibility purposes
 */
abstract contract OAppAuth is OAppAuthSender, OAppAuthReceiver {

    /**
     * @dev Constructor to initialize the OApp with the provided endpoint and owner.
     * @param _endpoint The address of the LOCAL LayerZero endpoint.
     * @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
     */
    constructor(address _endpoint, address _delegate) OAppAuthCore(_endpoint, _delegate) { }

    /**
     * @notice Retrieves the OApp version information.
     * @return senderVersion The version of the OAppSender.sol implementation.
     * @return receiverVersion The version of the OAppReceiver.sol implementation.
     */
    function oAppVersion()
        public
        pure
        virtual
        override(OAppAuthSender, OAppAuthReceiver)
        returns (uint64 senderVersion, uint64 receiverVersion)
    {
        return (SENDER_VERSION, RECEIVER_VERSION);
    }

}
