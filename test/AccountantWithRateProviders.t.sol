// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { GenericRateProvider } from "src/helper/GenericRateProvider.sol";
import { ETH_PER_WEETH_CHAINLINK } from "src/helper/Constants.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

interface IChainlink {
    function latestAnswer() external view returns (uint256);
}

contract AccountantWithRateProvidersTest is Test, MainnetAddresses {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    BoringVault public boringVault;
    AccountantWithRateProviders public accountant;
    address public payout_address = vm.addr(7_777_777);
    RolesAuthority public rolesAuthority;
    GenericRateProvider public mETHRateProvider;
    GenericRateProvider public ptRateProvider;

    uint8 public constant MINTER_ROLE = 1;
    uint8 public constant ADMIN_ROLE = 2;
    uint8 public constant UPDATE_EXCHANGE_RATE_ROLE = 3;
    uint8 public constant BORING_VAULT_ROLE = 4;

    event Paused();

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19_827_152;
        _startFork(rpcKey, blockNumber);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 18);

        accountant = new AccountantWithRateProviders(
            address(this), address(boringVault), payout_address, 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0, 0
        );

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        accountant.setAuthority(rolesAuthority);
        boringVault.setAuthority(rolesAuthority);

        // Setup roles authority.
        rolesAuthority.setRoleCapability(MINTER_ROLE, address(boringVault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.pause.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.unpause.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.updateDelay.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.updateUpper.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.updateLower.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.updateManagementFee.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.updatePayoutAddress.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(accountant), AccountantWithRateProviders.setRateProviderData.selector, true
        );
        rolesAuthority.setRoleCapability(
            UPDATE_EXCHANGE_RATE_ROLE,
            address(accountant),
            AccountantWithRateProviders.updateExchangeRate.selector,
            true
        );
        rolesAuthority.setRoleCapability(
            BORING_VAULT_ROLE, address(accountant), AccountantWithRateProviders.claimFees.selector, true
        );

        // Allow the boring vault to receive ETH.
        rolesAuthority.setPublicCapability(address(boringVault), bytes4(0), true);

        rolesAuthority.setUserRole(address(this), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(this), UPDATE_EXCHANGE_RATE_ROLE, true);
        rolesAuthority.setUserRole(address(boringVault), BORING_VAULT_ROLE, true);
        deal(address(WETH), address(this), 1000e18);
        WETH.safeApprove(address(boringVault), 1000e18);
        boringVault.enter(address(this), WETH, 1000e18, address(address(this)), 1000e18);

        AccountantWithRateProviders.RateProviderData[] memory rateProviderData =
            new AccountantWithRateProviders.RateProviderData[](1);
        rateProviderData[0] = AccountantWithRateProviders.RateProviderData(true, address(0), "");
        accountant.setRateProviderData(EETH, rateProviderData);
        rateProviderData = new AccountantWithRateProviders.RateProviderData[](2);
        // getRate() on WEETH rate provider
        rateProviderData[0] = AccountantWithRateProviders.RateProviderData(false, WEETH_RATE_PROVIDER, hex"679aefce");
        // latestAnswer() on ETH_PER_WEETH_CHAINLINK
        rateProviderData[1] =
            AccountantWithRateProviders.RateProviderData(false, address(ETH_PER_WEETH_CHAINLINK), hex"50d25bcd");
        accountant.setRateProviderData(WEETH, rateProviderData);
    }

    function testPause() external {
        accountant.pause();

        (,,,,,,,, bool is_paused,,,) = accountant.accountantState();
        assertTrue(is_paused == true, "Accountant should be paused");

        accountant.unpause();

        (,,,,,,,, is_paused,,,) = accountant.accountantState();

        assertTrue(is_paused == false, "Accountant should be unpaused");
    }

    function testUpdateDelay() external {
        accountant.updateDelay(2);

        (,,,,,,,,, uint32 delay_in_seconds,,) = accountant.accountantState();

        assertEq(delay_in_seconds, 2, "Delay should be 2 seconds");
    }

    function testUpdateUpper() external {
        accountant.updateUpper(1.002e4);
        (,,,,, uint16 upper_bound,,,,,,) = accountant.accountantState();

        assertEq(upper_bound, 1.002e4, "Upper bound should be 1.002e4");
    }

    function testUpdateLower() external {
        accountant.updateLower(0.998e4);
        (,,,,,, uint16 lower_bound,,,,,) = accountant.accountantState();

        assertEq(lower_bound, 0.998e4, "Lower bound should be 0.9980e4");
    }

    function testUpdateManagementFee() external {
        accountant.updateManagementFee(0.09e4);
        (,,,,,,,,,, uint16 management_fee,) = accountant.accountantState();

        assertEq(management_fee, 0.09e4, "Management Fee should be 0.09e4");
    }

    function testUpdatePerformanceFee() external {
        accountant.updatePerformanceFee(0.2e4);
        (,,,,,,,,,,, uint16 performance_fee) = accountant.accountantState();

        assertEq(performance_fee, 0.2e4, "Performance Fee should be 0.2e4");
    }

    function testUpdatePayoutAddress() external {
        (address payout,,,,,,,,,,,) = accountant.accountantState();
        assertEq(payout, payout_address, "Payout address should be the same");

        address new_payout_address = vm.addr(8_888_888);
        accountant.updatePayoutAddress(new_payout_address);

        (payout,,,,,,,,,,,) = accountant.accountantState();
        assertEq(payout, new_payout_address, "Payout address should be the same");
    }

    function testUpdateRateProvider() external {
        (bool isPeggedToBase, address rateProvider,) = accountant.rateProviderData(WEETH, 0);
        assertTrue(isPeggedToBase == false, "WEETH 1 should not be pegged to base");
        assertEq(rateProvider, WEETH_RATE_PROVIDER, "WEETH rate provider 1 should be set");
        (isPeggedToBase, rateProvider,) = accountant.rateProviderData(WEETH, 1);
        assertTrue(isPeggedToBase == false, "WEETH 2 should not be pegged to base");
        assertEq(rateProvider, address(ETH_PER_WEETH_CHAINLINK), "WEETH rate provider 2 should be set");
    }

    function testUpdateExchangeRateAndFeeLogic() external {
        accountant.updateManagementFee(0.01e4);
        accountant.updatePerformanceFee(0.2e4);

        skip(1 days / 24);
        // Increase exchange rate by 5 bps.
        uint96 new_exchange_rate = uint96(1.0005e18);
        accountant.updateExchangeRate(new_exchange_rate);

        (
            ,
            uint128 fees_owed,
            uint128 total_shares,
            uint96 current_exchange_rate,
            uint96 highestExchangeRate,
            ,
            ,
            uint64 last_update_timestamp,
            bool is_paused,
            ,
            ,
        ) = accountant.accountantState();
        assertEq(fees_owed, 0, "Fees owed should be 0");
        assertEq(total_shares, 1000e18, "Total shares should be 1_000e18");
        assertEq(current_exchange_rate, new_exchange_rate, "Current exchange rate should be updated");
        assertEq(highestExchangeRate, new_exchange_rate, "highestExchangeRate should be the current one");
        assertEq(last_update_timestamp, uint64(block.timestamp), "Last update timestamp should be updated");
        assertTrue(is_paused == false, "Accountant should not be paused");

        skip(1 days / 24);
        // Increase exchange rate by 5 bps.
        new_exchange_rate = uint96(1.001e18);
        accountant.updateExchangeRate(new_exchange_rate);

        // management fee
        uint256 expected_fees_owed =
            uint256(0.01e4).mulDivDown(uint256(1 days / 24).mulDivDown(1000.5e18, 365 days), 1e4);

        // performance fee
        expected_fees_owed += uint256(0.2e4).mulDivDown(1001e18 - 1000.5e18, 1e4);

        (, fees_owed, total_shares, current_exchange_rate, highestExchangeRate,,, last_update_timestamp, is_paused,,,) =
            accountant.accountantState();
        assertEq(fees_owed, expected_fees_owed, "Fees owed should equal expected");
        assertEq(total_shares, 1000e18, "Total shares should be 1_000e18");
        assertEq(current_exchange_rate, new_exchange_rate, "Current exchange rate should be updated");
        assertEq(highestExchangeRate, new_exchange_rate, "highestExchangeRate should be the current one");
        assertEq(last_update_timestamp, uint64(block.timestamp), "Last update timestamp should be updated");
        assertTrue(is_paused == false, "Accountant should not be paused");

        skip(1 days / 24);
        // Decrease exchange rate by 5 bps.
        new_exchange_rate = uint96(1.0005e18);
        accountant.updateExchangeRate(new_exchange_rate);

        expected_fees_owed += uint256(0.01e4).mulDivDown(uint256(1 days / 24).mulDivDown(1000.5e18, 365 days), 1e4);

        skip(1 days / 24);
        expected_fees_owed += uint256(0.01e4).mulDivDown(uint256(1 days / 24).mulDivDown(1000.5e18, 365 days), 1e4);

        // increase the exchange rate a little but not past the highest
        new_exchange_rate = uint96(1.0007e18);
        accountant.updateExchangeRate(new_exchange_rate);
        (,,,, highestExchangeRate,,,, is_paused,,,) = accountant.accountantState();
        assertEq(highestExchangeRate, 1.001e18, "highestExchangeRate should still be the old one");

        // reset the highest exchange rate then increase a little but not past the last highest
        accountant.resetHighestExchangeRate();
        // new_exchange_rate = uint96(1.0008e18);
        // accountant.updateExchangeRate(new_exchange_rate);

        (,,,, highestExchangeRate,,,,,,,) = accountant.accountantState();
        assertEq(highestExchangeRate, 1.0007e18, "highestExchangeRate should be the new one after reset");

        (, fees_owed, total_shares, current_exchange_rate,,,, last_update_timestamp, is_paused,,,) =
            accountant.accountantState();
        assertEq(fees_owed, expected_fees_owed, "Fees owed should equal expected");
        assertEq(total_shares, 1000e18, "Total shares should be 1_000e18");
        assertEq(current_exchange_rate, new_exchange_rate, "Current exchange rate should be updated");
        assertEq(last_update_timestamp, uint64(block.timestamp), "Last update timestamp should be updated");
        assertTrue(is_paused == false, "Accountant should not be paused");

        // Trying to update before the minimum time should succeed but, pause the contract.
        new_exchange_rate = uint96(1.0e18);
        vm.expectEmit();
        emit Paused();
        accountant.updateExchangeRate(new_exchange_rate);

        (, fees_owed, total_shares, current_exchange_rate,,,, last_update_timestamp, is_paused,,,) =
            accountant.accountantState();
        assertEq(fees_owed, expected_fees_owed, "Fees owed should equal expected");
        assertEq(total_shares, 1000e18, "Total shares should be 1_000e18");
        assertEq(current_exchange_rate, 1.0005e18, "Current exchange rate should NOT be updated");
        uint64 timestampBefore = uint64(block.timestamp);
        assertEq(last_update_timestamp, timestampBefore, "Last update timestamp should be updated");
        assertTrue(is_paused == true, "Accountant should be paused");

        accountant.unpause();

        // Or if the next update is outside the accepted bounds it will pause.
        skip((1 days / 24));
        new_exchange_rate = uint96(10.0e18);
        vm.expectEmit();
        emit Paused();
        accountant.updateExchangeRate(new_exchange_rate);

        (, fees_owed, total_shares, current_exchange_rate,,,, last_update_timestamp, is_paused,,,) =
            accountant.accountantState();
        assertEq(fees_owed, expected_fees_owed, "Fees owed should equal expected");
        assertEq(total_shares, 1000e18, "Total shares should be 1_000e18");
        assertEq(current_exchange_rate, 1.0005e18, "Current exchange rate should NOT be updated");
        assertEq(last_update_timestamp, timestampBefore, "Last update timestamp should NOT be updated");
        assertTrue(is_paused == true, "Accountant should be paused");
    }

    function testClaimFees() external {
        accountant.updateManagementFee(0.01e4);
        accountant.updatePerformanceFee(0.2e4);

        skip(1 days / 24);
        // Increase exchange rate by 5 bps.
        uint96 new_exchange_rate = uint96(1.0005e18);
        accountant.updateExchangeRate(new_exchange_rate);

        (, uint128 fees_owed,,,,,,,,,,) = accountant.accountantState();
        assertEq(fees_owed, 0, "Fees owed should be 0");

        skip(1 days / 24);
        // Increase exchange rate by 5 bps.
        new_exchange_rate = uint96(1.001e18);
        accountant.updateExchangeRate(new_exchange_rate);

        uint256 expected_fees_owed =
            uint256(0.01e4).mulDivDown(uint256(1 days / 24).mulDivDown(1000.5e18, 365 days), 1e4);

        // performance fee
        expected_fees_owed += uint256(0.2e4).mulDivDown(1001e18 - 1000.5e18, 1e4);

        (, fees_owed,,,,,,,,,,) = accountant.accountantState();
        assertEq(fees_owed, expected_fees_owed, "Fees owed should equal expected");

        vm.startPrank(address(boringVault));
        WETH.safeApprove(address(accountant), fees_owed);
        accountant.claimFees(WETH);
        vm.stopPrank();

        assertEq(WETH.balanceOf(payout_address), fees_owed, "Payout address should have received fees");

        skip(1 days / 24);
        // Increase exchange rate by 5 bps.
        new_exchange_rate = uint96(1.0015e18);
        accountant.updateExchangeRate(new_exchange_rate);

        deal(address(WEETH), address(boringVault), 1e18);
        vm.startPrank(address(boringVault));
        WEETH.safeApprove(address(accountant), 1e18);
        accountant.claimFees(WEETH);
        vm.stopPrank();
    }

    function testRates() external {
        // getRate and getRate in quote should work.
        uint256 rate = accountant.getRate();
        uint256 expected_rate = 1e18;
        assertEq(rate, expected_rate, "Rate should be expected rate");

        // Get deposit and withdraw rates from accountant
        uint256 depositRate = accountant.getDepositRate(WEETH);
        uint256 withdrawRate = accountant.getWithdrawRate(WEETH);

        // Get rates directly from providers
        uint256 chainlinkRate = IChainlink(address(ETH_PER_WEETH_CHAINLINK)).latestAnswer();
        uint256 weethRate = IRateProvider(address(WEETH_RATE_PROVIDER)).getRate();

        // Verify withdraw rate is lower than deposit rate
        assertLt(withdrawRate, depositRate, "Withdraw rate should be lower than deposit rate");

        // Verify rates match either Chainlink or WEETH provider
        bool matchesChainlink = depositRate == chainlinkRate || withdrawRate == chainlinkRate;
        bool matchesWeeth = depositRate == weethRate || withdrawRate == weethRate;
        assertTrue(matchesChainlink || matchesWeeth, "Rates should match either Chainlink or WEETH provider");
    }

    function testMETHRateProvider() external {
        // Deploy GenericRateProvider for mETH.
        uint256 amount = 1e18;
        bytes memory rateCalldata = abi.encodeWithSignature("mETHToETH(uint256)", amount);
        uint256 rate = MantleLspStaking(mantleLspStaking).mETHToETH(1e18);
        uint256 gas = gasleft();
        console.log("Gas used: ", gas - gasleft());

        // Setup rate in accountant.
        AccountantWithRateProviders.RateProviderData[] memory rateProviderData =
            new AccountantWithRateProviders.RateProviderData[](1);
        rateProviderData[0] = AccountantWithRateProviders.RateProviderData(false, mantleLspStaking, rateCalldata);
        accountant.setRateProviderData(METH, rateProviderData);

        console.log("accountant.getRate()", accountant.getRate());
        uint256 expectedRateInMeth = accountant.getRate().mulDivDown(1e18, rate);

        uint256 rateInMeth = accountant.getWithdrawRate(METH);

        assertEq(rateInMeth, expectedRateInMeth, "Rate should be expected rate");

        assertLt(rateInMeth, 1e18, "Rate should be less than 1e18");
    }

    function testPtRateProvider() external {
        // Deploy GenericRateProvider for mETH.
        uint256 amount = 1e18;
        bytes32 pt = 0x000000000000000000000000c69Ad9baB1dEE23F4605a82b3354F8E40d1E5966; // pendleEethPt
        bytes32 quote = 0x000000000000000000000000C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // wETH
        bytes memory rateCalldata =
            abi.encodeWithSignature("getValue(address,uint256,address)", pt, bytes32(amount), quote);

        // Setup rate in accountant.
        AccountantWithRateProviders.RateProviderData[] memory rateProviderData =
            new AccountantWithRateProviders.RateProviderData[](1);
        rateProviderData[0] =
            AccountantWithRateProviders.RateProviderData(false, address(liquidV1PriceRouter), rateCalldata);
        accountant.setRateProviderData(ERC20(pendleEethPt), rateProviderData);

        uint256 rate = PriceRouter(address(liquidV1PriceRouter)).getValue(pendleEethPt, 1e18, address(WETH));
        uint256 expectedRateInPt = accountant.getRate().mulDivDown(1e18, rate);

        uint256 rateInPt = accountant.getWithdrawRate(ERC20(pendleEethPt));

        assertEq(rateInPt, expectedRateInPt, "Rate should be expected rate");

        assertGt(rateInPt, 1e18, "Rate should be greater than 1e18");
    }

    function testReverts() external {
        accountant.pause();

        vm.expectRevert(
            abi.encodeWithSelector(AccountantWithRateProviders.AccountantWithRateProviders__Paused.selector)
        );
        accountant.updateExchangeRate(0);

        address attacker = vm.addr(1);
        vm.startPrank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccountantWithRateProviders.AccountantWithRateProviders__OnlyCallableByBoringVault.selector
            )
        );
        accountant.claimFees(WETH);
        vm.stopPrank();

        vm.startPrank(address(boringVault));
        vm.expectRevert(
            abi.encodeWithSelector(AccountantWithRateProviders.AccountantWithRateProviders__Paused.selector)
        );
        accountant.claimFees(WETH);
        vm.stopPrank();

        accountant.unpause();

        vm.startPrank(address(boringVault));
        vm.expectRevert(
            abi.encodeWithSelector(AccountantWithRateProviders.AccountantWithRateProviders__ZeroFeesOwed.selector)
        );
        accountant.claimFees(WETH);
        vm.stopPrank();

        // Trying to claimFees with unsupported token should revert.
        vm.startPrank(address(boringVault));
        vm.expectRevert();
        accountant.claimFees(ETHX);
        vm.stopPrank();

        accountant.pause();

        vm.expectRevert(
            abi.encodeWithSelector(AccountantWithRateProviders.AccountantWithRateProviders__Paused.selector)
        );
        accountant.updateExchangeRate(0);

        // Updating bounds, and management fee reverts.
        vm.expectRevert(
            abi.encodeWithSelector(AccountantWithRateProviders.AccountantWithRateProviders__UpperBoundTooSmall.selector)
        );
        accountant.updateUpper(0.9999e4);

        vm.expectRevert(
            abi.encodeWithSelector(AccountantWithRateProviders.AccountantWithRateProviders__LowerBoundTooLarge.selector)
        );
        accountant.updateLower(1.0001e4);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccountantWithRateProviders.AccountantWithRateProviders__ManagementFeeTooLarge.selector
            )
        );
        accountant.updateManagementFee(0.2001e4);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccountantWithRateProviders.AccountantWithRateProviders__UpdateDelayTooLarge.selector
            )
        );
        accountant.updateDelay(14 days + 1);
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}

interface MantleLspStaking {
    function mETHToETH(uint256) external view returns (uint256);
}

interface PriceRouter {
    function getValue(address, uint256, address) external view returns (uint256);
}
