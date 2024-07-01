// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {CrossChainTellerBase, BridgeData, ERC20} from "./CrossChainTellerBase.sol";
import {OAppAuth, MessagingFee, Origin } from "./OAppAuth/OAppAuth.sol";
import {console} from "@forge-std/Test.sol";
import {Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import {Auth} from "@solmate/auth/Auth.sol";

contract CrossChainLayerZeroTellerWithMultiAssetSupport is CrossChainTellerBase, OAppAuth{
    
    constructor(address _owner, address _vault, address _accountant, address _weth, address _endpoint)
        CrossChainTellerBase(_owner, _vault, _accountant, _weth)
        OAppAuth(_endpoint, _owner) 
    {

    }

    // Some arbitrary data you want to deliver to the destination chain!
    string public data;

    /**
     * @notice Sends a message from the source to destination chain.
     * @param _dstEid Destination chain's endpoint ID.
     * @param _message The message to send.
     * @param _options Message execution options (e.g., for sending gas to destination).
     */
    function send(
        uint32 _dstEid,
        string memory _message,
        bytes calldata _options
    ) external payable {
        // Encodes the message before invoking _lzSend.
        // Replace with whatever data you want to send!
        bytes memory _payload = abi.encode(_message);
        _lzSend(
            _dstEid,
            _payload,
            _options,
            // Fee in native gas and ZRO token.
            MessagingFee(msg.value, 0),
            // Refund address in case of failed source message.
            payable(msg.sender)
        );
    }

    /**
     * @dev Called when data is received from the protocol. It overrides the equivalent function in the parent contract.
     * Protocol messages are defined as packets, comprised of the following parameters.
     * @param _origin A struct containing information about where the packet came from.
     * @param _guid A global unique identifier for tracking the packet.
     * @param payload Encoded message.
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata payload,
        address,  // Executor address as specified by the OApp.
        bytes calldata  // Any extra data or options to trigger on receipt.
    ) internal override {
        // Decode the payload to get the message
        // In this case, type is string, but depends on your encoding!
        data = abi.decode(payload, (string));
    }
    
    function _bridge(BridgeData calldata data) internal override returns(bytes32){
        return 0;
    }

}