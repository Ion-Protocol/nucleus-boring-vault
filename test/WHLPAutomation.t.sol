// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { MockCoreWriter } from "test/resources/MockCoreWriter.sol";
import { HLPAccount } from "src/whlp-automation/HLPAccount.sol";

contract WHLPAutomation is Test {
    MockCoreWriter mockCoreWriter;

    event MockCoreWriter__LimitOrder(
        uint32 asset, bool isBuy, uint64 limitPx, uint64 sz, bool reduceOnly, uint8 encodedTif, uint128 cloid
    );
    event MockCoreWriter__VaultTransfer(address vault, bool isDeposit, uint64 usd);
    event MockCoreWriter__TokenDelegate(address validator, uint64 _wei, bool isUndelegate);
    event MockCoreWriter__StakingDeposit(uint64 _wei);
    event MockCoreWriter__StakingWithdraw(uint64 _wei);
    event MockCoreWriter__SpotSend(address destination, uint64 token, uint64 _wei);
    event MockCoreWriter__UsdClassTransfer(uint64 ntl, bool toPerp);
    event MockCoreWriter__FinalizeEvmContract(
        uint64 token, uint8 encodedFinalizeEvmContractVariant, uint64 createNonce
    );
    event MockCoreWriter__AddApiWallet(address apiWalletAddress, string apiWalletName);

    function setUp() external {
        mockCoreWriter = new MockCoreWriter();
    }

    // test the account in isolation
    function testHLPAccount() external {
        HLPAccount account = new HLPAccount(address(this), address(mockCoreWriter));

        // Assume some funds are sent on L1

        // transfer 100e6 USDC from spot to perps
        vm.expectEmit();
        emit MockCoreWriter__UsdClassTransfer(100e6, true);
        account.toPerps(100e6);

        // deposit 100e6 USDC to HLP
        vm.expectEmit();
        emit MockCoreWriter__VaultTransfer(account.HLP_VAULT(), true, 100e6);
        account.depositHLP(100e6);

        // withdraw 50e6 USDC from HLP
        vm.expectEmit();
        emit MockCoreWriter__VaultTransfer(account.HLP_VAULT(), false, 50e6);
        account.withdrawHLP(50e6);

        // transfer 50e6 USDC to spot
        vm.expectEmit();
        emit MockCoreWriter__UsdClassTransfer(50e6, false);
        account.toSpot(50e6);

        // withdraw 50e6 USDC to owner
        vm.expectEmit();
        emit MockCoreWriter__SpotSend(address(this), account.USDC_ID(), 50e6);
        account.withdrawSpot(50e6);
    }
}
