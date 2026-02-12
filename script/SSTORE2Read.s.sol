// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Script } from "forge-std/Script.sol";
import { SSTORE2 } from "lib/solmate/src/utils/SSTORE2.sol";
import { console } from "forge-std/console.sol";

/**
 * @title SSTORE2Read
 * @notice Simple script to read SSTORE2 storage contents
 * @dev Example: forge script script/SSTORE2Read.s.sol --sig "read(address)" 0x1234567890123456789012345678901234567890
 */
contract SSTORE2Read is Script {

    using SSTORE2 for address;

    function read(address pointer) public view {
        // Read the data from SSTORE2 storage
        bytes memory data = pointer.read();

        // Print the raw bytes
        console.logBytes(data);
    }

}
