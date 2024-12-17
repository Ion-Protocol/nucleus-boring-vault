// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

contract BaseTokenStandIn {
    uint8 public immutable decimals;

    constructor(uint8 _decimals) {
        decimals = _decimals;
    }

}
