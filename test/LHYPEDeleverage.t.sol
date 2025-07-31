// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { LHYPEDeleverage } from "src/helper/LHYPEDeleverage.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";

contract LHYPEDeleverageTest is Test, MainnetAddresses {
    using stdStorage for StdStorage;

    ERC20 WHYPE_DEBT = ERC20(0x37E44F3070b5455f1f5d7aaAd9Fc8590229CC5Cb);
    ERC20 wstHYPE_COLLATERAL = ERC20(0xC8b6E0acf159E058E22c564C0C513ec21f8a1Bf5);

    BoringVault public boringVault;
    AccountantWithRateProviders public accountant;
    LHYPEDeleverage public lhypeDeleverage;
    RolesAuthority public rolesAuthority;

    IPool public pool = IPool(0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b);

    function setUp() external {
        // Setup forked environment. On Hyperliquid
        string memory rpcKey = "HL_RPC_URL";
        uint256 blockNumber = 9_902_287;
        _startFork(rpcKey, blockNumber);

        boringVault = BoringVault(payable(0x5748ae796AE46A4F1348a1693de4b50560485562));
        accountant = AccountantWithRateProviders(0xcE621a3CA6F72706678cFF0572ae8d15e5F001c3);
        rolesAuthority = RolesAuthority(0xDc4605f2332Ba81CdB5A6f84cB1a6356198D11f6);
        lhypeDeleverage = new LHYPEDeleverage();

        vm.prank(rolesAuthority.owner());
        rolesAuthority.setUserRole(address(lhypeDeleverage), 2, true);
    }

    function test_deleverage_fails_when_health_factor_below_minimum() public {
        uint256 hypeToDeleverage = 10_000e18;
        uint256 maxStHypeWithdrawn = 10_053e18;
        uint256 minimumEndingHealthFactor = 1_190_000_000_000_000_000;
        uint256 realEndingHealthFactor = 1_184_405_334_333_582_561;

        vm.prank(address(boringVault));
        vm.expectRevert(
            abi.encodeWithSelector(
                LHYPEDeleverage.LHYPEDeleverage__HealthFactorBelowMinimum.selector,
                realEndingHealthFactor,
                minimumEndingHealthFactor
            )
        );
        lhypeDeleverage.deleverage(hypeToDeleverage, maxStHypeWithdrawn, minimumEndingHealthFactor);
    }

    function test_deleverage_fails_when_slippage_too_high() public {
        uint256 hypeToDeleverage = 10_000e18;
        uint256 maxStHypeWithdrawn = 10_040e18;
        uint256 realStHypeWithdrawn = 10_052_578_589_887_917_685_505;
        uint256 minimumEndingHealthFactor = 1_170_000_000_000_000_000;

        vm.prank(address(boringVault));
        vm.expectRevert(
            abi.encodeWithSelector(
                LHYPEDeleverage.LHYPEDeleverage__SlippageTooHigh.selector, realStHypeWithdrawn, maxStHypeWithdrawn
            )
        );
        lhypeDeleverage.deleverage(hypeToDeleverage, maxStHypeWithdrawn, minimumEndingHealthFactor);
    }

    function test_deleverage() public {
        // TODO: More accurate numbers here
        uint256 hypeToDeleverage = 10_000e18;
        uint256 maxStHypeWithdrawn = 10_053e18;

        (uint256 totalCollateralBaseBefore, uint256 totalDebtBaseBefore,,,, uint256 healthFactorBefore) =
            pool.getUserAccountData(address(boringVault));

        uint256 debtBefore = WHYPE_DEBT.balanceOf(address(boringVault));
        uint256 collateralBefore = wstHYPE_COLLATERAL.balanceOf(address(boringVault));

        vm.prank(address(boringVault));
        uint256 val = lhypeDeleverage.deleverage(hypeToDeleverage, maxStHypeWithdrawn, healthFactorBefore);

        // TODO: assert that the health factor is what is expected from that

        (uint256 totalCollateralBaseAfter, uint256 totalDebtBaseAfter,,,, uint256 healthFactorAfter) =
            pool.getUserAccountData(address(boringVault));

        uint256 debtAfter = WHYPE_DEBT.balanceOf(address(boringVault));
        uint256 collateralAfter = wstHYPE_COLLATERAL.balanceOf(address(boringVault));

        console.log("collateralBefore", collateralBefore);
        console.log("collateralAfter", collateralAfter);
        console.log("debtBefore", debtBefore);
        console.log("debtAfter", debtAfter);
        console.log("totalCollateralBaseBefore", totalCollateralBaseBefore);
        console.log("totalCollateralBaseAfter", totalCollateralBaseAfter);
        console.log("totalDebtBaseBefore", totalDebtBaseBefore);
        console.log("totalDebtBaseAfter", totalDebtBaseAfter);
        console.log("healthFactor before", healthFactorBefore);
        console.log("healthFactor after", healthFactorAfter);

        assertGt(healthFactorAfter, healthFactorBefore, "Health factor should improve");
        // assertEq(debtAfter, debtBefore - hypeToDeleverage);
        // assertLt(ltvAfter, ltvBefore);
        // assertLt(ltvAfter, maxLTV);
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}
