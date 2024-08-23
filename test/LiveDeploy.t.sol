// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { DeployAll } from "script/deploy/deployAll.s.sol";
import { ConfigReader } from "script/ConfigReader.s.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";

// We use this so that we can use the inheritance linearization to start the fork before other constructors
abstract contract ForkTest is Test {
    constructor() {
        _startFork("MAINNET_RPC_URL");
    }

    function _startFork(string memory rpcKey) internal virtual returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey));
        vm.selectFork(forkId);
    }
}

contract LiveDeploy is ForkTest, DeployAll {
    using FixedPointMathLib for uint256;

    uint256 ONE_SHARE;
    uint8 constant SOLVER_ROLE = 42;

    function setUp() public virtual {
        // we have to start the fork again... I don't exactly know why
        _startFork("MAINNET_RPC_URL");

        // Setup forked environment.
        run("exampleL1.json");

        ONE_SHARE = 10 ** BoringVault(payable(mainConfig.boringVault)).decimals();

        // give this the SOLVER_ROLE to call bulkWithdraw
        RolesAuthority rolesAuthority = RolesAuthority(mainConfig.rolesAuthority);
        vm.startPrank(mainConfig.protocolAdmin);
        rolesAuthority.setUserRole(address(this), SOLVER_ROLE, true);
        rolesAuthority.setRoleCapability(SOLVER_ROLE, mainConfig.teller, TellerWithMultiAssetSupport.bulkWithdraw.selector, true);
        vm.stopPrank();
    }

    function testDepositBaseAsset(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, 10_000e18);
        _depositAssetWithApprove(ERC20(mainConfig.base), depositAmount);

        BoringVault boringVault = BoringVault(payable(mainConfig.boringVault));
        uint256 expected_shares = depositAmount;
        assertEq(
            boringVault.balanceOf(address(this)),
            expected_shares,
            "Should have received expected shares 1:1 for base asset"
        );

        // attempt a withdrawal after
        TellerWithMultiAssetSupport(mainConfig.teller).bulkWithdraw(ERC20(mainConfig.base), expected_shares, depositAmount, address(this));
        assertEq(ERC20(mainConfig.base).balanceOf(address(this)), depositAmount, "Should have been able to withdraw back the depositAmount");
    }

    function testDepositASupportedAsset(uint256 depositAmount, uint256 indexOfSupported) public {
        uint256 assetsCount = mainConfig.assets.length;
        indexOfSupported = bound(indexOfSupported, 0, assetsCount);
        depositAmount = bound(depositAmount, 1, 10_000e18);

        uint256 expecteShares;
        AccountantWithRateProviders accountant = AccountantWithRateProviders(mainConfig.accountant);
        uint[] memory expectedSharesByAsset = new uint[](assetsCount);
        for (uint256 i; i < assetsCount; ++i) {
            expectedSharesByAsset[i] = 
                depositAmount.mulDivDown(ONE_SHARE, accountant.getRateInQuoteSafe(ERC20(mainConfig.assets[i])));
            expecteShares += expectedSharesByAsset[i];
            
            _depositAssetWithApprove(ERC20(mainConfig.assets[i]), depositAmount);
        }

        BoringVault boringVault = BoringVault(payable(mainConfig.boringVault));
        assertEq(boringVault.balanceOf(address(this)), expecteShares, "Should have received expected shares");

        // withdrawal the assets for the same amount back
        for(uint256 i; i < assetsCount; ++i){
            TellerWithMultiAssetSupport(mainConfig.teller).bulkWithdraw(ERC20(mainConfig.assets[i]), expectedSharesByAsset[i], depositAmount-1, address(this));
            assertApproxEqAbs(ERC20(mainConfig.assets[i]).balanceOf(address(this)), depositAmount, 1, "Should have been able to withdraw back the depositAmounts");
        }

    }

    function _depositAssetWithApprove(ERC20 asset, uint256 depositAmount) internal {
        deal(address(asset), address(this), depositAmount);
        asset.approve(mainConfig.boringVault, depositAmount);
        TellerWithMultiAssetSupport(mainConfig.teller).deposit(asset, depositAmount, depositAmount);
    }
}
