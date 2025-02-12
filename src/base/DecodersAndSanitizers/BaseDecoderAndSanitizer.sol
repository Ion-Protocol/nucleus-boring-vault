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

    constructor(address _boringVault) {
        boringVault = _boringVault;
    }

    function approve(address spender, uint256) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(spender);
    }
}
