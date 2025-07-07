// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { MockCoreWriter } from "test/resources/MockCoreWriter.sol";

contract WHLPAutomation is Test {
    MockCoreWrtier mockCoreWriter;

    function setUp() external {
        mockCoreWriter = new MockCoreWriter();
    }

    // test the account in isolation
    function testHLPAccount() external {
        HLPAccount account = new HLPAccount(address(this));

        // Assume some funds are sent on L1

        // transfer 100e6 USDC from spot to perps
        vm.expectEmit(abi.encodeWithSelector(MockCoreWriter.MockCoreWriter__UsdClassTransfer.selctor, 100e6, true));
        account.toPerps(100e6);

        // deposit 100e6 USDC to HLP
        vm.expectEmit(
            abi.encodeWithSelector(
                MockCoreWriter.MockCoreWriter__VaultTransfer.selctor, account.HLP_VAULT(), true, 100e6
            )
        );
        account.depositHLP(100e6);

        // withdraw 50e6 USDC from HLP
        vm.expectEmit(
            abi.encodeWithSelector(
                MockCoreWriter.MockCoreWriter__VaultTransfer.selctor, account.HLP_VAULT(), false, 50e6
            )
        );
        account.withdrawHLP(50e6);

        // transfer 50e6 USDC to spot
        vm.expectEmit(abi.encodeWithSelector(MockCoreWriter.MockCoreWriter__UsdClassTransfer.selctor, 50e6, false));
        account.toSpot(50e6);

        // withdraw 50e6 USDC to owner
        vm.expectEmit(
            abi.encodeWithSelector(
                MockCoreWriter.MockCoreWriter__SpotSend.selctor, address(this), account.USDC_ID(), 50e6
            )
        );
        account.withdrawSpot(50e6);
    }
}
