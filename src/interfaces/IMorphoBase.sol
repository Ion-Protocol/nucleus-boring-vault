// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IMorphoBase {
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}
