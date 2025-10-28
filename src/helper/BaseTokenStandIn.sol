// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

contract BaseTokenStandIn {

    uint8 public immutable decimals;
    string public name;

    constructor(string memory _name, uint8 _decimals) {
        name = _name;
        decimals = _decimals;
    }

}
