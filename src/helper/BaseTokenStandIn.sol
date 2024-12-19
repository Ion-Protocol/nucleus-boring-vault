// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { STAND_IN_TOKEN_NAME } from "./Constants.sol";

contract BaseTokenStandIn {
    uint8 public immutable decimals;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }

    function name() external pure returns (string memory) {
        return STAND_IN_TOKEN_NAME;
    }
}
