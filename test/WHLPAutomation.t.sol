// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { MockCoreWriter } from "test/resources/MockCoreWriter.sol";
import { HLPAccount } from "src/whlp-automation/HLPAccount.sol";
import { HLPController } from "src/whlp-automation/HLPController.sol";

contract WHLPAutomation is Test {

    MockCoreWriter mockCoreWriter;
    HLPController controller;

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
        _startFork("HL_RPC_URL");
        mockCoreWriter = new MockCoreWriter();
        controller = new HLPController(address(this), address(mockCoreWriter));
    }

    // test the account in isolation
    function testHLPAccount() external {
        address vault = makeAddr("a vault");
        HLPAccount account = new HLPAccount(address(this), vault, address(mockCoreWriter));

        // Assume some funds are sent on L1

        // transfer 100e6 USDC from spot to perp
        vm.expectEmit();
        emit MockCoreWriter__UsdClassTransfer(100e6, true);
        account.toPerp(100e6);

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
        emit MockCoreWriter__SpotSend(vault, account.USDC_INDEX(), 50e6);
        account.withdrawSpot(50e6);
    }

    function testControllerHappyPath() external {
        controller.deployAccounts(10);

        HLPAccount account = HLPAccount(controller.getAccountAt(2));
        vm.expectEmit(address(mockCoreWriter));
        emit MockCoreWriter__UsdClassTransfer(100e6, true);
        vm.expectEmit(address(mockCoreWriter));
        emit MockCoreWriter__VaultTransfer(account.HLP_VAULT(), true, 100e6);

        controller.deposit(account, 100e6);

        vm.expectEmit(address(mockCoreWriter));
        emit MockCoreWriter__VaultTransfer(account.HLP_VAULT(), false, 100e6);
        vm.expectEmit(address(mockCoreWriter));
        emit MockCoreWriter__UsdClassTransfer(100e6, false);
        controller.withdraw(account, 100e6);

        vm.expectEmit(address(mockCoreWriter));
        // note vault is the owner, but in this test we are the owner
        emit MockCoreWriter__SpotSend(address(this), account.USDC_INDEX(), 100e6);

        controller.sendToVault(account, 100e6);
    }

    function _startFork(string memory rpcKey) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey));
        vm.selectFork(forkId);
    }

}
