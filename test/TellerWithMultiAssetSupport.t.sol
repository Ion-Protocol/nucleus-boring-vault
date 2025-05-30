// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { ILiquidityPool } from "src/interfaces/IStaking.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { AtomicSolverV3, AtomicQueue } from "src/atomic-queue/AtomicSolverV3.sol";
import { ETH_PER_WEETH_CHAINLINK } from "src/helper/Constants.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

contract TellerWithMultiAssetSupportTest is Test, MainnetAddresses {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    BoringVault public boringVault;

    uint8 public constant ADMIN_ROLE = 1;
    uint8 public constant MINTER_ROLE = 7;
    uint8 public constant BURNER_ROLE = 8;
    uint8 public constant SOLVER_ROLE = 9;
    uint8 public constant QUEUE_ROLE = 10;
    uint8 public constant CAN_SOLVE_ROLE = 11;

    TellerWithMultiAssetSupport public teller;
    AccountantWithRateProviders public accountant;
    address public payout_address = vm.addr(7_777_777);
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ERC20 internal constant NATIVE_ERC20 = ERC20(NATIVE);
    RolesAuthority public rolesAuthority;
    AtomicQueue public atomicQueue;
    AtomicSolverV3 public atomicSolverV3;

    address public solver = vm.addr(54);
    uint256 ONE_SHARE;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 21_769_049;
        _startFork(rpcKey, blockNumber);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 18);
        ONE_SHARE = 10 ** boringVault.decimals();

        accountant = new AccountantWithRateProviders(
            address(this), address(boringVault), payout_address, 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0, 0
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

        AccountantWithRateProviders.RateProviderData[] memory rateProviderData =
            new AccountantWithRateProviders.RateProviderData[](1);
        rateProviderData[0] = AccountantWithRateProviders.RateProviderData(true, address(0), "");
        accountant.setRateProviderData(EETH, rateProviderData);
        rateProviderData = new AccountantWithRateProviders.RateProviderData[](2);
        // WEETH rate provider getRate()
        rateProviderData[0] = AccountantWithRateProviders.RateProviderData(false, WEETH_RATE_PROVIDER, hex"679aefce");
        // ETH_PER_WEETH_CHAINLINK latestAnswer()
        rateProviderData[1] =
            AccountantWithRateProviders.RateProviderData(false, address(ETH_PER_WEETH_CHAINLINK), hex"50d25bcd");
        accountant.setRateProviderData(WEETH, rateProviderData);
    }

    function testDepositReverting(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);
        // Turn on share lock period, and deposit reverting
        boringVault.setBeforeTransferHook(address(teller));

        teller.setShareLockPeriod(1 days);

        uint256 wETH_amount = amount;
        deal(address(WETH), address(this), wETH_amount);
        uint256 eETH_amount = amount;
        deal(address(this), eETH_amount + 1);
        ILiquidityPool(EETH_LIQUIDITY_POOL).deposit{ value: eETH_amount + 1 }();

        WETH.safeApprove(address(boringVault), wETH_amount);
        EETH.safeApprove(address(boringVault), eETH_amount);
        uint256 shares0 = teller.deposit(WETH, wETH_amount, 0, address(this));
        uint256 firstDepositTimestamp = block.timestamp;
        // Skip 1 days to finalize first deposit.
        skip(1 days + 1);
        uint256 shares1 = teller.deposit(EETH, eETH_amount, 0, address(this));
        uint256 secondDepositTimestamp = block.timestamp;

        // Even if setShareLockPeriod is set to 2 days, first deposit is still not revertable.
        teller.setShareLockPeriod(2 days);

        // If depositReverter tries to revert the first deposit, call fails.
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__SharesAreUnLocked.selector)
        );
        teller.refundDeposit(1, address(this), address(WETH), wETH_amount, shares0, firstDepositTimestamp, 1 days);

        // However the second deposit is still revertable.
        teller.refundDeposit(2, address(this), address(EETH), eETH_amount, shares1, secondDepositTimestamp, 1 days);

        // Calling revert deposit again should revert.
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__BadDepositHash.selector)
        );
        teller.refundDeposit(2, address(this), address(EETH), eETH_amount, shares1, secondDepositTimestamp, 1 days);
    }

    function testSupplyCap() external {
        ERC20[] memory assets = new ERC20[](1);
        assets[0] = WETH;
        deal(address(WETH), address(this), 1e18);

        teller.setSupplyCap(1e18);
        WETH.approve(address(boringVault), 1e18);

        teller.deposit(WETH, 0.5e18, 0, address(this));
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__SupplyCapReached.selector)
        );
        teller.deposit(WETH, 0.51e18, 0, address(this));
    }

    function testDepositCap() external {
        ERC20[] memory assets = new ERC20[](1);
        assets[0] = WETH;

        uint112[] memory rateLimits = new uint112[](1);
        rateLimits[0] = type(uint112).max;

        uint128[] memory depositCaps = new uint128[](1);
        depositCaps[0] = 100e18;

        bool[] memory withdrawStatusByAssets = new bool[](1);
        withdrawStatusByAssets[0] = true;

        teller.configureAssets(assets, rateLimits, depositCaps, withdrawStatusByAssets);
        uint256 wETH_amount = 50e18;
        deal(address(WETH), address(this), wETH_amount + 51e18);

        WETH.safeApprove(address(boringVault), wETH_amount + 51e18);
        uint256 shares0 = teller.deposit(WETH, wETH_amount, 0, address(this));

        assertGt(shares0, 0, "should have received shares");

        wETH_amount = 51e18; // Defaut is 100 so try and deposit more
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__DepositCapReached.selector)
        );
        uint256 shares1 = teller.deposit(WETH, wETH_amount, 0, address(this));

        vm.warp(block.timestamp + 1 + teller.rateLimitPeriod());
        // unlike with rate limit, deposit cap is not reset after rate limit period
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__DepositCapReached.selector)
        );
        uint256 shares2 = teller.deposit(WETH, wETH_amount, 0, address(this));
    }

    function testDepositRateLimit() external {
        ERC20[] memory assets = new ERC20[](1);
        assets[0] = WETH;

        uint112[] memory rateLimits = new uint112[](1);
        rateLimits[0] = 100e18;

        uint128[] memory depositCaps = new uint128[](1);
        depositCaps[0] = type(uint128).max;

        bool[] memory withdrawStatusByAssets = new bool[](1);
        withdrawStatusByAssets[0] = true;

        teller.configureAssets(assets, rateLimits, depositCaps, withdrawStatusByAssets);
        uint256 wETH_amount = 50e18;
        deal(address(WETH), address(this), wETH_amount + 51e18);

        WETH.safeApprove(address(boringVault), wETH_amount + 51e18);
        uint256 shares0 = teller.deposit(WETH, wETH_amount, 0, address(this));

        assertGt(shares0, 0, "should have received shares");

        wETH_amount = 51e18; // Defaut is 100 so try and deposit more
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__RateLimit.selector)
        );
        uint256 shares1 = teller.deposit(WETH, wETH_amount, 0, address(this));

        vm.warp(block.timestamp + 1 + teller.rateLimitPeriod());
        uint256 shares2 = teller.deposit(WETH, wETH_amount, 0, address(this));
        assertGt(shares2, 0, "should have received shares after warp past rate limit period");
    }

    function testUserDepositPeggedAssets(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        uint256 wETH_amount = amount;
        deal(address(WETH), address(this), wETH_amount);
        uint256 eETH_amount = amount;
        deal(address(this), eETH_amount + 1);
        ILiquidityPool(EETH_LIQUIDITY_POOL).deposit{ value: eETH_amount + 1 }();

        WETH.safeApprove(address(boringVault), wETH_amount);
        EETH.safeApprove(address(boringVault), eETH_amount);

        teller.deposit(WETH, wETH_amount, 0, address(this));
        teller.deposit(EETH, eETH_amount, 0, address(this));

        uint256 expected_shares = 2 * amount;

        assertEq(boringVault.balanceOf(address(this)), expected_shares, "Should have received expected shares");
    }

    function testUserDepositNonPeggedAssets(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        uint256 weETH_amount = amount.mulDivDown(1e18, IRateProvider(WEETH_RATE_PROVIDER).getRate());
        deal(address(WEETH), address(this), weETH_amount);

        WEETH.safeApprove(address(boringVault), weETH_amount);

        teller.deposit(WEETH, weETH_amount, 0, address(this));

        uint256 expected_shares = teller.accountant().getSharesForDepositAmount(WEETH, weETH_amount);

        assertApproxEqRel(
            boringVault.balanceOf(address(this)), expected_shares, 0.000001e18, "Should have received expected shares"
        );
    }

    function testUserPermitDeposit(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        uint256 userKey = 111;
        address user = vm.addr(userKey);

        uint256 weETH_amount = amount.mulDivDown(1e18, IRateProvider(WEETH_RATE_PROVIDER).getRate());
        deal(address(WEETH), user, weETH_amount);
        // function sign(uint256 privateKey, bytes32 digest) external pure returns (uint8 v, bytes32 r, bytes32 s);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                WEETH.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(boringVault),
                        weETH_amount,
                        WEETH.nonces(user),
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);

        vm.startPrank(user);
        teller.depositWithPermit(WEETH, weETH_amount, 0, block.timestamp, user, v, r, s);
        vm.stopPrank();

        // and if user supplied wrong permit data, deposit will fail.
        digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                WEETH.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(boringVault),
                        weETH_amount,
                        WEETH.nonces(user),
                        block.timestamp
                    )
                )
            )
        );
        (v, r, s) = vm.sign(userKey, digest);

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__PermitFailedAndAllowanceTooLow.selector
            )
        );
        teller.depositWithPermit(WEETH, weETH_amount, 0, block.timestamp, user, v, r, s);
        vm.stopPrank();
    }

    function testUserPermitDepositWithFrontRunning(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        uint256 userKey = 111;
        address user = vm.addr(userKey);

        uint256 weETH_amount = amount.mulDivDown(1e18, IRateProvider(WEETH_RATE_PROVIDER).getRate());
        deal(address(WEETH), user, weETH_amount);
        // function sign(uint256 privateKey, bytes32 digest) external pure returns (uint8 v, bytes32 r, bytes32 s);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                WEETH.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(boringVault),
                        weETH_amount,
                        WEETH.nonces(user),
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);

        // Assume attacker seems users TX in the mem pool and tries griefing them by calling `permit` first.
        address attacker = vm.addr(0xDEAD);
        vm.startPrank(attacker);
        WEETH.permit(user, address(boringVault), weETH_amount, block.timestamp, v, r, s);
        vm.stopPrank();

        // Users TX is still successful.
        vm.startPrank(user);
        teller.depositWithPermit(WEETH, weETH_amount, 0, block.timestamp, user, v, r, s);
        vm.stopPrank();

        assertTrue(boringVault.balanceOf(user) > 0, "Should have received shares");
    }

    function testBulkDeposit(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        uint256 wETH_amount = amount;
        deal(address(WETH), address(this), wETH_amount);
        uint256 eETH_amount = amount;
        deal(address(this), eETH_amount + 1);
        ILiquidityPool(EETH_LIQUIDITY_POOL).deposit{ value: eETH_amount + 1 }();
        uint256 depositRate = teller.accountant().getDepositRate(WEETH);
        uint256 weETH_amount = amount.mulDivDown(1e18, depositRate);
        deal(address(WEETH), address(this), weETH_amount);

        WETH.safeApprove(address(boringVault), wETH_amount);
        EETH.safeApprove(address(boringVault), eETH_amount);
        WEETH.safeApprove(address(boringVault), weETH_amount);

        teller.deposit(WETH, wETH_amount, 0, address(this));
        teller.deposit(EETH, eETH_amount, 0, address(this));
        teller.deposit(WEETH, weETH_amount, 0, address(this));

        uint256 expected_shares = 3 * amount;

        assertApproxEqRel(
            boringVault.balanceOf(address(this)), expected_shares, 0.0001e18, "Should have received expected shares"
        );
    }

    function testBulkWithdraw(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        uint256 wETH_amount = amount;
        deal(address(WETH), address(this), wETH_amount);
        uint256 eETH_amount = amount;
        deal(address(this), eETH_amount + 1);
        ILiquidityPool(EETH_LIQUIDITY_POOL).deposit{ value: eETH_amount + 1 }();
        uint256 weETH_amount = amount.mulDivDown(1e18, IRateProvider(WEETH_RATE_PROVIDER).getRate());
        deal(address(WEETH), address(this), weETH_amount);

        WETH.safeApprove(address(boringVault), wETH_amount);
        EETH.safeApprove(address(boringVault), eETH_amount);
        WEETH.safeApprove(address(boringVault), weETH_amount);

        uint256 shares_0 = teller.deposit(WETH, wETH_amount, 0, address(this));
        uint256 shares_1 = teller.deposit(EETH, eETH_amount, 0, address(this));
        uint256 shares_2 = teller.deposit(WEETH, weETH_amount, 0, address(this));

        uint256 assets_out_0 = teller.bulkWithdraw(WETH, shares_0, 0, address(this));
        uint256 assets_out_1 = teller.bulkWithdraw(EETH, shares_1, 0, address(this));
        uint256 assets_out_2 = teller.bulkWithdraw(WEETH, shares_2, 0, address(this));

        assertApproxEqAbs(assets_out_0, wETH_amount, 1, "Should have received expected wETH assets");
        assertApproxEqAbs(assets_out_1, eETH_amount, 1, "Should have received expected eETH assets");
        assertApproxEqRel(assets_out_2, weETH_amount, 0.25e18, "Should have received expected weETH assets");
        assertLt(
            assets_out_2,
            weETH_amount,
            "Should have received less than weETH assets due to the rate being in protocol favor"
        );
    }

    function testWithdrawWithAtomicQueue(uint256 amount) external {
        amount = bound(amount, 0.0001e18, 10_000e18);

        address user = vm.addr(9);
        uint256 wETH_amount = amount;
        deal(address(WETH), user, wETH_amount);

        vm.startPrank(user);
        WETH.safeApprove(address(boringVault), wETH_amount);

        uint256 shares = teller.deposit(WETH, wETH_amount, 0, user);

        // Share lock period is not set, so user can submit withdraw request immediately.
        AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 1 days),
            atomicPrice: 1e18,
            offerAmount: uint96(shares),
            inSolve: false
        });
        boringVault.approve(address(atomicQueue), shares);
        atomicQueue.updateAtomicRequest(boringVault, WETH, req);
        vm.stopPrank();

        // Solver approves solver contract to spend enough assets to cover withdraw.
        vm.startPrank(solver);
        WETH.safeApprove(address(atomicSolverV3), wETH_amount);
        // Solve withdraw request.
        address[] memory users = new address[](1);
        users[0] = user;
        atomicSolverV3.redeemSolve(atomicQueue, boringVault, WETH, users, 0, type(uint256).max, teller);
        vm.stopPrank();
    }

    function testAssetIsSupported() external {
        assertTrue(teller.isWithdrawSupported(WETH) == true, "WETH withdraw should be supported");

        ERC20[] memory assets = new ERC20[](1);
        assets[0] = WETH;

        uint112[] memory rateLimits = new uint112[](1);
        rateLimits[0] = 0;

        uint128[] memory depositCaps = new uint128[](1);
        depositCaps[0] = type(uint128).max;

        bool[] memory withdrawStatusByAssets = new bool[](1);
        withdrawStatusByAssets[0] = false;

        teller.configureAssets(assets, rateLimits, depositCaps, withdrawStatusByAssets);
        assertTrue(teller.isWithdrawSupported(WETH) == false, "WETH should not be supported");

        (, uint112 rateLimit,,,) = teller.limitByAsset(address(WETH));

        assertEq(rateLimit, 0, "Should have 0 rate limit");

        rateLimits[0] = type(uint112).max;
        withdrawStatusByAssets[0] = true;
        teller.configureAssets(assets, rateLimits, depositCaps, withdrawStatusByAssets);

        assertTrue(teller.isWithdrawSupported(WETH) == true, "WETH withdraw should be supported");
    }

    function testMaxTimeFromLastUpdateOnDeposit() external {
        accountant.updateExchangeRate(1.1e18);
        teller.setMaxTimeFromLastUpdate(1 days);

        require(accountant.getLastUpdateTimestamp() == block.timestamp, "Last update timestamp should be set");

        vm.warp(block.timestamp + 1 days + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__MaxTimeFromLastUpdateExceeded.selector
            )
        );
        teller.deposit(WETH, 0, 0, address(this));
    }

    function testMaxTimeFromLastUpdateOnBulkWithdraw() external {
        accountant.updateExchangeRate(1.1e18);
        teller.setMaxTimeFromLastUpdate(1 days);

        require(accountant.getLastUpdateTimestamp() == block.timestamp, "Last update timestamp should be set");

        vm.warp(block.timestamp + 1 days + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__MaxTimeFromLastUpdateExceeded.selector
            )
        );
        teller.bulkWithdraw(WETH, 0, 0, address(this));
    }

    function testReverts() external {
        // Test pause logic
        teller.pause();

        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__Paused.selector)
        );
        teller.deposit(WETH, 0, 0, address(this));

        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__Paused.selector)
        );
        teller.depositWithPermit(WETH, 0, 0, 0, address(this), 0, bytes32(0), bytes32(0));

        teller.unpause();

        ERC20[] memory assets = new ERC20[](1);
        assets[0] = WETH;

        uint112[] memory rateLimits = new uint112[](1);
        rateLimits[0] = 0;

        uint128[] memory depositCaps = new uint128[](1);
        depositCaps[0] = type(uint128).max;

        bool[] memory withdrawStatusByAssets = new bool[](1);
        withdrawStatusByAssets[0] = true;

        teller.configureAssets(assets, rateLimits, depositCaps, withdrawStatusByAssets);

        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__AssetDepositNotSupported.selector
            )
        );
        teller.deposit(WETH, 0, 0, address(this));

        rateLimits[0] = type(uint112).max;
        teller.configureAssets(assets, rateLimits, depositCaps, withdrawStatusByAssets);

        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__ZeroAssets.selector)
        );
        teller.deposit(WETH, 0, 0, address(this));

        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__MinimumMintNotMet.selector)
        );
        teller.deposit(WETH, 1, type(uint256).max, address(this));

        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__AssetDepositNotSupported.selector
            )
        );
        teller.deposit(NATIVE_ERC20, 0, 0, address(this));

        // bulkWithdraw reverts
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__ZeroShares.selector)
        );
        teller.bulkWithdraw(WETH, 0, 0, address(this));

        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__MinimumAssetsNotMet.selector
            )
        );
        teller.bulkWithdraw(WETH, 1, type(uint256).max, address(this));

        // Set share lock reverts
        vm.expectRevert(
            abi.encodeWithSelector(
                TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__ShareLockPeriodTooLong.selector
            )
        );
        teller.setShareLockPeriod(3 days + 1);

        teller.setShareLockPeriod(3 days);
        boringVault.setBeforeTransferHook(address(teller));

        // Have user deposit
        address user = vm.addr(333);
        vm.startPrank(user);
        uint256 wETH_amount = 1e18;
        deal(address(WETH), user, wETH_amount);
        WETH.safeApprove(address(boringVault), wETH_amount);

        teller.deposit(WETH, wETH_amount, 0, user);

        // Trying to transfer shares should revert.
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__SharesAreLocked.selector)
        );
        boringVault.transfer(address(this), 1);

        vm.stopPrank();
        // Calling transferFrom should also revert.
        vm.expectRevert(
            abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__SharesAreLocked.selector)
        );
        boringVault.transferFrom(user, address(this), 1);

        // But if user waits 3 days.
        skip(3 days + 1);
        // They can now transfer.
        vm.prank(user);
        boringVault.transfer(address(this), 1);
    }

    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}
