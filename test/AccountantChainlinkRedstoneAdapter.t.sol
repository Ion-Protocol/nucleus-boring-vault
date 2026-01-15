// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { AccountantChainlinkRedstoneAdapter } from "src/helper/AccountantChainlinkRedstoneAdapter.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

contract AccountantChainlinkRedstoneAdapterTest is Test, MainnetAddresses {

    using SafeTransferLib for ERC20;

    BoringVault public boringVault;
    AccountantWithRateProviders public accountant;
    AccountantChainlinkRedstoneAdapter public adapter;
    address public payout_address = vm.addr(7_777_777);
    RolesAuthority public rolesAuthority;

    uint8 public constant MINTER_ROLE = 1;
    uint8 public constant ADMIN_ROLE = 2;
    uint8 public constant UPDATE_EXCHANGE_RATE_ROLE = 3;

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

        // Setup minimal roles
        rolesAuthority.setRoleCapability(MINTER_ROLE, address(boringVault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(
            UPDATE_EXCHANGE_RATE_ROLE,
            address(accountant),
            AccountantWithRateProviders.updateExchangeRate.selector,
            true
        );

        rolesAuthority.setUserRole(address(this), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(this), UPDATE_EXCHANGE_RATE_ROLE, true);

        // Add some funds to test with
        deal(address(WETH), address(this), 1000e18);
        WETH.safeApprove(address(boringVault), 1000e18);
        boringVault.enter(address(this), WETH, 1000e18, address(this), 1000e18);

        // Deploy the adapter
        adapter = new AccountantChainlinkRedstoneAdapter(address(this), accountant);
    }

    function testLatestRoundDataReturnsAccountantRate() external {
        // Get the rate directly from accountant
        uint256 accountantRate = accountant.getRate();

        // Get the rate from the adapter
        (, int256 adapterAnswer,,,) = adapter.latestRoundData();

        // They should be equal
        assertEq(uint256(adapterAnswer), accountantRate, "Adapter should return same rate as accountant");

        // Test with updated exchange rate
        accountant.updateExchangeRate(1.5e18);

        uint256 newAccountantRate = accountant.getRate();
        (, int256 newAdapterAnswer,,,) = adapter.latestRoundData();

        assertEq(uint256(newAdapterAnswer), newAccountantRate, "Adapter should return updated rate");
    }

    function testDecimalsMatchAccountant() external {
        uint8 accountantDecimals = accountant.decimals();
        uint8 adapterDecimals = adapter.decimals();

        assertEq(adapterDecimals, accountantDecimals, "Adapter decimals should match accountant decimals");
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }

}
