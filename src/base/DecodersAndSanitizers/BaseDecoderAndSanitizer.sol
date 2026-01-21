// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// solhint-disable-next-line no-unused-import
import { DecoderCustomTypes } from "src/interfaces/DecoderCustomTypes.sol";

contract BaseDecoderAndSanitizer {

    //============================== IMMUTABLES ===============================

    /**
     * @notice The BoringVault contract address.
     */
    address internal immutable boringVault;

    error BaseDecoderAndSanitizer__FunctionNotImplemented(bytes _calldata);

    constructor(address _boringVault) {
        boringVault = _boringVault;
    }

    // @desc The spender address to approve
    // @tag spender:address
    function approve(address spender, uint256) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(spender);
    }

    function acceptOwnership() external pure returns (bytes memory addressesFound) {
        // Nothing to decode
    }

    // @desc The new owner address
    // @tag newOwner:address
    function transferOwnership(address newOwner) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(newOwner);
    }

    // @desc transfer an ERC20
    // @tag to:address:The recipient of the ERC20
    function transfer(address to, uint256 value) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(to);
    }

    fallback() external {
        revert BaseDecoderAndSanitizer__FunctionNotImplemented(msg.data);
    }

}
