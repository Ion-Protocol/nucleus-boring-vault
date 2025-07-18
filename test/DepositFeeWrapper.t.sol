// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test, stdStorage } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { RateProviderConfig } from "src/base/Roles/RateProviderConfig.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { ILiquidityPool } from "src/interfaces/IStaking.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { AtomicSolverV3, AtomicQueue } from "src/atomic-queue/AtomicSolverV3.sol";
import { ETH_PER_WEETH_CHAINLINK } from "src/helper/Constants.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { DepositFeeWrapper } from "src/helper/DepositFeeWrapper.sol";

contract DepositFeeWrapperTest is Test, MainnetAddresses {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    BoringVault public boringVault;

    uint8 public constant ADMIN_ROLE = 1;
    uint8 public constant MINTER_ROLE = 7;
    uint8 public constant BURNER_ROLE = 8;
    uint8 public constant SOLVER_ROLE = 9;
    uint8 public constant QUEUE_ROLE = 10;
    uint8 public constant CAN_SOLVE_ROLE = 11;

    TellerWithMultiAssetSupport public teller;
    DepositFeeWrapper public depositFeeWrapper;

    AccountantWithRateProviders public accountant;
    RateProviderConfig public rateProviderContract;

    address public payout_address = vm.addr(7_777_777);
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ERC20 internal constant NATIVE_ERC20 = ERC20(NATIVE);
    RolesAuthority public rolesAuthority;
    AtomicQueue public atomicQueue;
    AtomicSolverV3 public atomicSolverV3;

    address public solver = vm.addr(54);
    address public feeReceiver = vm.addr(55);
    uint256 ONE_SHARE;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 21_769_049;
        _startFork(rpcKey, blockNumber);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 18);
        rateProviderContract = new RateProviderConfig(address(this));
        ONE_SHARE = 10 ** boringVault.decimals();

        accountant = new AccountantWithRateProviders(
            address(this),
            address(boringVault),
            payout_address,
            1e18,
            address(WETH),
            1.001e4,
            0.999e4,
            1,
            0,
            0,
            rateProviderContract
        );

        teller = new TellerWithMultiAssetSupport(address(this), address(boringVault), address(accountant));

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));

        atomicQueue = new AtomicQueue();
        atomicSolverV3 = new AtomicSolverV3(address(this), rolesAuthority);

        boringVault.setAuthority(rolesAuthority);
        accountant.setAuthority(rolesAuthority);
        teller.setAuthority(rolesAuthority);

        rolesAuthority.setRoleCapability(MINTER_ROLE, address(boringVault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(boringVault), BoringVault.exit.selector, true);
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(teller), TellerWithMultiAssetSupport.configureAssets.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(teller), TellerWithMultiAssetSupport.refundDeposit.selector, true
        );
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setRoleCapability(QUEUE_ROLE, address(atomicSolverV3), AtomicSolverV3.finishSolve.selector, true);
        rolesAuthority.setRoleCapability(
            CAN_SOLVE_ROLE, address(atomicSolverV3), AtomicSolverV3.redeemSolve.selector, true
        );
        rolesAuthority.setPublicCapability(address(teller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(
            address(teller), TellerWithMultiAssetSupport.depositWithPermit.selector, true
        );

        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicSolverV3), SOLVER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicQueue), QUEUE_ROLE, true);
        rolesAuthority.setUserRole(solver, CAN_SOLVE_ROLE, true);

        ERC20[] memory assets = new ERC20[](3);
        assets[0] = WETH;
        assets[1] = EETH;
        assets[2] = WEETH;

        teller.addAssets(assets);

        RateProviderConfig.RateProviderData[] memory rateProviderData = new RateProviderConfig.RateProviderData[](1);

        rateProviderData[0] = RateProviderConfig.RateProviderData(true, address(0), "", 0, type(uint256).max);
        rateProviderContract.setRateProviderData(WETH, EETH, rateProviderData);

        rateProviderData = new RateProviderConfig.RateProviderData[](2);
        // WEETH rate provider getRate()
        rateProviderData[0] =
            RateProviderConfig.RateProviderData(false, WEETH_RATE_PROVIDER, hex"679aefce", 0, type(uint256).max);
        // ETH_PER_WEETH_CHAINLINK latestAnswer()
        rateProviderData[1] = RateProviderConfig.RateProviderData(
            false, address(ETH_PER_WEETH_CHAINLINK), hex"50d25bcd", 0, type(uint256).max
        );
        rateProviderContract.setRateProviderData(WETH, WEETH, rateProviderData);

        depositFeeWrapper = new DepositFeeWrapper(address(this));
        depositFeeWrapper.setFeeReceiver(feeReceiver);
    }

    function testUserDepositPeggedAssetsDepositFee(uint256 amount, uint256 depositFee) external {
        depositFee = bound(depositFee, 0.0001e4, 9999);
        amount = bound(amount, 0.0001e18, 10_000e18);
        depositFeeWrapper.setFeePercentage(depositFee);

        uint256 wETH_amount = amount;
        deal(address(WETH), address(this), wETH_amount);
        uint256 eETH_amount = amount;
        deal(address(this), eETH_amount + 1);
        ILiquidityPool(EETH_LIQUIDITY_POOL).deposit{ value: eETH_amount + 1 }();

        WETH.safeApprove(address(depositFeeWrapper), wETH_amount);
        EETH.safeApprove(address(depositFeeWrapper), eETH_amount);

        depositFeeWrapper.deposit(teller, WETH, wETH_amount, 0, address(this));
        depositFeeWrapper.deposit(teller, EETH, eETH_amount, 0, address(this));

        uint256 feesWETH = (wETH_amount * depositFee / 1e4);
        uint256 feesEETH = (eETH_amount * depositFee / 1e4);
        uint256 expected_shares = (2 * amount) - feesWETH - feesEETH;

        assertEq(boringVault.balanceOf(address(this)), expected_shares, "Should have received expected shares");
        assertEq(WETH.balanceOf(feeReceiver), feesWETH, "Should have received expected WETH fees");
        assertApproxEqAbs(EETH.balanceOf(feeReceiver), feesEETH, 2, "Should have received expected EETH fees");
    }

    function testUserDepositNonPeggedAssetsDepositFee(uint256 amount, uint256 depositFee) public {
        depositFee = bound(depositFee, 0.0001e4, 9999);
        amount = bound(amount, 0.0001e18, 10_000e18);
        depositFeeWrapper.setFeePercentage(depositFee);

        uint256 weETH_amount = amount.mulDivDown(1e18, IRateProvider(WEETH_RATE_PROVIDER).getRate());

        uint256 fees = _depositReturnFees(weETH_amount, WEETH, depositFee);
        uint256 weETH_amount_after_fee = weETH_amount - fees;
        uint256 expected_shares = teller.accountant().getSharesForDepositAmount(WEETH, weETH_amount_after_fee);

        assertApproxEqRel(
            boringVault.balanceOf(address(this)), expected_shares, 0.000001e18, "Should have received expected shares"
        );
        assertEq(WEETH.balanceOf(feeReceiver), fees, "Should have received expected fees");
    }

    function testOwnerCanSetFeeReceiver() external {
        address newFeeReceiver = vm.addr(5555);
        if (newFeeReceiver == address(0)) {
            vm.expectRevert(DepositFeeWrapper.DepositFeeWrapper__ZeroAddress.selector);
            depositFeeWrapper.setFeeReceiver(newFeeReceiver);
            return;
        }
        depositFeeWrapper.setFeeReceiver(newFeeReceiver);
        assertEq(depositFeeWrapper.feeReceiver(), newFeeReceiver, "Should have set fee receiver");

        depositFeeWrapper.setFeePercentage(0.03e4);
        uint256 fees = _depositReturnFees(1e18, WEETH, 0.03e4);
        assertEq(WEETH.balanceOf(newFeeReceiver), fees, "Should have received expected fees");
    }

    function testReverts() external {
        // Test non-owner cannot change fee receiver
        vm.startPrank(address(1));
        vm.expectRevert();
        // vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector), address(1));
        depositFeeWrapper.setFeeReceiver(address(2));

        // Test non-owner cannot change fee percentage
        vm.expectRevert();
        // vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector), address(1));
        depositFeeWrapper.setFeePercentage(0.1e4);

        vm.stopPrank();
        // Test cannot set fee greater than 100%
        vm.expectRevert();
        depositFeeWrapper.setFeePercentage(1.1e4);
    }

    function _depositReturnFees(uint256 amount, ERC20 asset, uint256 depositFee) internal returns (uint256 fees) {
        deal(address(asset), address(this), amount);

        asset.safeApprove(address(depositFeeWrapper), amount);

        depositFeeWrapper.deposit(teller, asset, amount, 0, address(this));

        fees = (amount * depositFee / 1e4);
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}
