// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseWithdrawQueueTest, console } from "../BaseWithdrawQueueTest.t.sol";
import { WithdrawQueue } from "src/base/Roles/WithdrawQueue.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract WithdrawQueueHappyPathTest is BaseWithdrawQueueTest {

    function testWithdrawQueueHappyPath() external {
        uint256 depositAmount1 = 1e6;

        deal(address(USDC), user, depositAmount1);

        vm.startPrank(user);
        USDC.approve(address(boringVault), depositAmount1);

        teller.deposit(ERC20(address(USDC)), depositAmount1, 0);

        assertEq(boringVault.balanceOf(user), depositAmount1, "user should have shares");

        boringVault.approve(address(withdrawQueue), depositAmount1);
        withdrawQueue.submitOrder(
            WithdrawQueue.SubmitOrderParams({
                amountOffer: depositAmount1,
                wantAsset: USDC,
                intendedDepositor: user,
                receiver: user,
                refundReceiver: user,
                signatureParams: defaultSignatureParams
            })
        );

        vm.stopPrank();
        assertEq(boringVault.balanceOf(user), 0, "user should have no shares");
        assertEq(boringVault.balanceOf(address(withdrawQueue)), depositAmount1, "queue should be holding shares");
        assertEq(USDC.balanceOf(address(boringVault)), depositAmount1, "vault should have USDC");
        assertEq(withdrawQueue.ownerOf(1), user, "User should own order 1");

        withdrawQueue.processOrders(1);
        assertEq(USDC.balanceOf(user), _getAmountAfterFees(depositAmount1), "User should have USDC - fees");
        assertEq(boringVault.balanceOf(feeRecipient), _getFees(depositAmount1), "fee recipient should have fees");
        assertEq(withdrawQueue.totalSupply(), 0, "total supply should be 0");
    }

}
