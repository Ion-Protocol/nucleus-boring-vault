// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { BoringVault } from "src/base/BoringVault.sol";

contract HLBoringVaultTest is Test {
    BoringVault public vault;
    address public deployer;

    function setUp() public {
        deployer = makeAddr("deployer");
        vault = new BoringVault(deployer, "Hyperliquid BoringVault", "HLBV", 18);
    }

    function test_SetDeployerAddress() public {
        // Call setDeployerAddress
        vm.prank(deployer);
        vault.setDeployerAddress(deployer);

        // Get the value from slot0
        bytes32 slot0 = vm.load(address(vault), bytes32(0));
        address storedDeployer = address(uint160(uint256(slot0)));

        // Assert that the stored deployer address matches the one we set
        assertEq(storedDeployer, deployer);
    }
}
