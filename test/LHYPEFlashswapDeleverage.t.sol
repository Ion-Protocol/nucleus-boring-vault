// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { LHYPEFlashswapDeleverage, IGetRate } from "src/helper/LHYPEFlashswapDeleverage.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract LHYPEDeleverageTest is Test, MainnetAddresses {
    using stdStorage for StdStorage;

    ERC20 WHYPE_DEBT_HFI = ERC20(0x37E44F3070b5455f1f5d7aaAd9Fc8590229CC5Cb);
    ERC20 wstHYPE_COLLATERAL_HFI = ERC20(0xC8b6E0acf159E058E22c564C0C513ec21f8a1Bf5);

    ERC20 WHYPE_DEBT_HLEND = ERC20(0x747d0d4Ba0a2083651513cd008deb95075683e82);
    ERC20 wstHYPE_COLLATERAL_HLEND = ERC20(0x0Ab8AAE3335Ed4B373A33D9023b6A6585b149D33);

    address wstHYPE = 0x94e8396e0869c9F2200760aF0621aFd240E1CF38;
    address stHYPE = 0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1;
    address WHYPE = 0x5555555555555555555555555555555555555555;

    IPool public hypurrfiPool_hfi = IPool(0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b);
    IPool public hyperlendPool_hlend = IPool(0x00A89d7a5A02160f20150EbEA7a2b5E4879A1A8b);
    IUniswapV3Pool public hyperswapPool = IUniswapV3Pool(0x8D64d8273a3D50E44Cc0e6F43d927f78754EdefB);

    BoringVault public boringVault;
    AccountantWithRateProviders public accountant;
    LHYPEFlashswapDeleverage public lhypeDeleverage_hfi;
    LHYPEFlashswapDeleverage public lhypeDeleverage_hlend;
    RolesAuthority public rolesAuthority;

    IPool public pool_hfi = IPool(0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b);

    uint256 wstHypeRate;

    function setUp() external {
        // Setup forked environment. On Hyperliquid
        string memory rpcKey = "HL_RPC_URL";
        uint256 blockNumber = 9_902_287;
        _startFork(rpcKey, blockNumber);

        wstHypeRate = IGetRate(stHYPE).balancePerShare();

        boringVault = BoringVault(payable(0x5748ae796AE46A4F1348a1693de4b50560485562));
        accountant = AccountantWithRateProviders(0xcE621a3CA6F72706678cFF0572ae8d15e5F001c3);
        rolesAuthority = RolesAuthority(0xDc4605f2332Ba81CdB5A6f84cB1a6356198D11f6);
        lhypeDeleverage_hfi =
            new LHYPEFlashswapDeleverage(address(hypurrfiPool_hfi), address(hyperswapPool), boringVault);
        lhypeDeleverage_hlend =
            new LHYPEFlashswapDeleverage(address(hyperlendPool_hlend), address(hyperswapPool), boringVault);
        vm.startPrank(rolesAuthority.owner());
        rolesAuthority.setUserRole(address(lhypeDeleverage_hfi), 2, true);
        rolesAuthority.setUserRole(address(lhypeDeleverage_hlend), 2, true);
        vm.stopPrank();
    }

    function test_deleverage_fails_when_health_factor_below_minimum_hfi() public {
        uint256 hypeToDeleverage = 10_000e18;
        uint256 maxStHypeWithdrawn = 10_055e18;
        uint256 minimumEndingHealthFactor = 1_190_000_000_000_000_000;
        uint256 realEndingHealthFactor = 1_184_497_487_209_156_735;

        vm.prank(address(boringVault));
        vm.expectRevert(
            abi.encodeWithSelector(
                LHYPEFlashswapDeleverage.LHYPEFlashswapDeleverage__HealthFactorBelowMinimum.selector,
                realEndingHealthFactor,
                minimumEndingHealthFactor
            )
        );
        lhypeDeleverage_hfi.deleverage(hypeToDeleverage, maxStHypeWithdrawn, minimumEndingHealthFactor);
    }

    function test_deleverage_fails_when_slippage_too_high_hfi() public {
        uint256 hypeToDeleverage = 10_000e18;
        uint256 maxStHypeWithdrawn = 10_000e18;
        uint256 realStHypeWithdrawn = 10_052_578_589_887_917_685_505;
        uint256 minimumEndingHealthFactor = 1_170_000_000_000_000_000;

        vm.prank(address(boringVault));
        vm.expectRevert(
            abi.encodeWithSelector(
                LHYPEFlashswapDeleverage.LHYPEFlashswapDeleverage__SlippageTooHigh.selector,
                realStHypeWithdrawn,
                maxStHypeWithdrawn
            )
        );
        lhypeDeleverage_hfi.deleverage(hypeToDeleverage, maxStHypeWithdrawn, minimumEndingHealthFactor);
    }

    /// @dev test that the deleverage will succeed no matter the values put in assuming generous enough bounds
    function test_can_deleverage_hfi(uint256 hypeToDeleverage) public {
        hypeToDeleverage = bound(hypeToDeleverage, 1, 40_000e18);
        uint256 maxStHypeWithdrawn = hypeToDeleverage * 10;
        vm.prank(address(boringVault));
        lhypeDeleverage_hfi.deleverage(hypeToDeleverage, maxStHypeWithdrawn, 1_050_000_000_000_000_000);
    }

    /// @dev test that the deleverage will succeed no matter the values put in assuming generous enough bounds
    function test_can_deleverage_hlend(uint256 hypeToDeleverage) public {
        hypeToDeleverage = bound(hypeToDeleverage, 1, 40_000e18);
        uint256 maxStHypeWithdrawn = hypeToDeleverage * 10;
        vm.prank(address(boringVault));
        lhypeDeleverage_hlend.deleverage(hypeToDeleverage, maxStHypeWithdrawn, 1_050_000_000_000_000_000);
    }

    function test_deleverage_hfi() public {
        // TODO: More accurate numbers here
        uint256 hypeToDeleverage = 10_000e18;
        uint256 maxStHypeWithdrawn = 10_053e18;

        (
            uint256 totalCollateralBaseBefore,
            uint256 totalDebtBaseBefore,
            ,
            uint256 liquidationThresholdBefore,
            ,
            uint256 healthFactorBefore
        ) = pool_hfi.getUserAccountData(address(boringVault));

        uint256 debtBefore = WHYPE_DEBT_HFI.balanceOf(address(boringVault));
        uint256 collateralBefore = wstHYPE_COLLATERAL_HFI.balanceOf(address(boringVault));

        vm.prank(address(boringVault));
        uint256 amountWstHypePaid =
            lhypeDeleverage_hfi.deleverage(hypeToDeleverage, maxStHypeWithdrawn, healthFactorBefore);
        console.log("liquidationThresholdBefore", liquidationThresholdBefore);

        uint256 expectedHealthFactor = ((collateralBefore - amountWstHypePaid) * wstHypeRate / 1e18)
            * liquidationThresholdBefore * 1e18 / (debtBefore - hypeToDeleverage) / 1e4; // divide 1e4 because liquidation
            // threshold has 4 decimals

        (uint256 totalCollateralBaseAfter, uint256 totalDebtBaseAfter,,,, uint256 healthFactorAfter) =
            pool_hfi.getUserAccountData(address(boringVault));

        console.log("collateralBefore", collateralBefore);
        // console.log("collateralAfter", collateralAfter);
        console.log("debtBefore", debtBefore);
        // console.log("debtAfter", debtAfter);
        console.log("totalCollateralBaseBefore", totalCollateralBaseBefore);
        console.log("totalCollateralBaseAfter", totalCollateralBaseAfter);
        console.log("totalDebtBaseBefore", totalDebtBaseBefore);
        console.log("totalDebtBaseAfter", totalDebtBaseAfter);
        console.log("healthFactor before", healthFactorBefore);
        console.log("healthFactor after", healthFactorAfter);

        assertApproxEqAbs(healthFactorAfter, expectedHealthFactor, 1e14);
        assertGt(healthFactorAfter, healthFactorBefore, "Health factor should improve");
    }

    // function test_deleverage_fails_when_health_factor_below_minimum_hlend() public {
    //     uint256 hypeToDeleverage = 10_000e18;
    //     uint256 maxStHypeWithdrawn = 10_053e18;
    //     uint256 minimumEndingHealthFactor = 1_190_000_000_000_000_000;
    //     uint256 realEndingHealthFactor = 1_184_405_334_333_582_561;

    //     vm.prank(address(boringVault));
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             LHYPEFlashswapDeleverage.LHYPEFlashswapDeleverage__HealthFactorBelowMinimum.selector,
    //             realEndingHealthFactor,
    //             minimumEndingHealthFactor
    //         )
    //     );
    //     lhypeDeleverage_hlend.deleverage(hypeToDeleverage, maxStHypeWithdrawn, minimumEndingHealthFactor);
    // }

    // function test_deleverage_fails_when_slippage_too_high_hlend() public {
    //     uint256 hypeToDeleverage = 10_000e18;
    //     uint256 maxStHypeWithdrawn = 10_040e18;
    //     uint256 realStHypeWithdrawn = 10_052_578_589_887_917_685_505;
    //     uint256 minimumEndingHealthFactor = 1_170_000_000_000_000_000;

    //     vm.prank(address(boringVault));
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             LHYPEFlashswapDeleverage.LHYPEFlashswapDeleverage__SlippageTooHigh.selector,
    //             realStHypeWithdrawn,
    //             maxStHypeWithdrawn
    //         )
    //     );
    //     lhypeDeleverage_hlend.deleverage(hypeToDeleverage, maxStHypeWithdrawn, minimumEndingHealthFactor);
    // }

    function test_deleverage_hlend() public {
        // TODO: More accurate numbers here
        uint256 hypeToDeleverage = 10_000e18;
        uint256 maxStHypeWithdrawn = 10_053e18;

        (
            uint256 totalCollateralBaseBefore,
            uint256 totalDebtBaseBefore,
            ,
            uint256 liquidationThresholdBefore,
            ,
            uint256 healthFactorBefore
        ) = hyperlendPool_hlend.getUserAccountData(address(boringVault));

        uint256 debtBefore = WHYPE_DEBT_HLEND.balanceOf(address(boringVault));
        uint256 collateralBefore = wstHYPE_COLLATERAL_HLEND.balanceOf(address(boringVault));

        vm.prank(address(boringVault));
        uint256 amountWstHypePaid =
            lhypeDeleverage_hlend.deleverage(hypeToDeleverage, maxStHypeWithdrawn, healthFactorBefore);
        console.log("liquidationThresholdBefore", liquidationThresholdBefore);

        uint256 expectedHealthFactor = ((collateralBefore - amountWstHypePaid) * wstHypeRate / 1e18)
            * liquidationThresholdBefore * 1e18 / (debtBefore - hypeToDeleverage) / 1e4; // divide 1e4 because liquidation
            // threshold has 4 decimals

        (uint256 totalCollateralBaseAfter, uint256 totalDebtBaseAfter,,,, uint256 healthFactorAfter) =
            hyperlendPool_hlend.getUserAccountData(address(boringVault));

        console.log("collateralBefore", collateralBefore);
        // console.log("collateralAfter", collateralAfter);
        console.log("debtBefore", debtBefore);
        // console.log("debtAfter", debtAfter);
        console.log("totalCollateralBaseBefore", totalCollateralBaseBefore);
        console.log("totalCollateralBaseAfter", totalCollateralBaseAfter);
        console.log("totalDebtBaseBefore", totalDebtBaseBefore);
        console.log("totalDebtBaseAfter", totalDebtBaseAfter);
        console.log("healthFactor before", healthFactorBefore);
        console.log("healthFactor after", healthFactorAfter);
        console.log("expectedHealthFactor", expectedHealthFactor);

        assertApproxEqAbs(healthFactorAfter, expectedHealthFactor, 1e14);
        assertGt(healthFactorAfter, healthFactorBefore, "Health factor should improve");
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}
