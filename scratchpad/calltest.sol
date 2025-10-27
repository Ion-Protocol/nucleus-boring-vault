// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

contract Fails {
    function foo() external payable;
}
contract CallTest {
    function callTest() public pure returns (string memory) {
        Fails f = new Fails();
        f.call{value:100}(Fails.foo.selector);
    }
}