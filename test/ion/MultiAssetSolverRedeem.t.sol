// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import {
    MultiAssetAtomicSolverRedeem,
    IAtomicQueue
} from "./../../src/atomic-queue/multi-asset-solvers/MultiAssetAtomicSolverRedeem.sol";
import { TellerWithMultiAssetSupport } from "./../../src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "./../../src/base/Roles/AccountantWithRateProviders.sol";
import { BoringVault } from "./../../src/base/BoringVault.sol";
import { EthPerWstEthRateProvider } from "./../../src/oracles/EthPerWstEthRateProvider.sol";
import { ETH_PER_STETH_CHAINLINK, WSTETH_ADDRESS } from "@ion-protocol/Constants.sol";
import { IonPoolSharedSetup } from "./IonPoolSharedSetup.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { StdUtils, IMulticall3 } from "forge-std/StdUtils.sol";
import { console2 } from "forge-std/console2.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { AtomicQueue } from "./../../src/atomic-queue/AtomicQueue.sol";

contract MultiAssetAtomicSolverRedeemTest is IonPoolSharedSetup {
    using FixedPointMathLib for uint256;

    MultiAssetAtomicSolverRedeem public solver;
    AtomicQueue public atomicQueue;

    ERC20 public offerToken;
    ERC20 public wantToken1;
    ERC20 public wantToken2;

    address immutable SOLVER_OWNER = makeAddr("MultiAssetAtomicSolver");
    uint8 public constant SOLVER_ROLE = 12;
    uint8 public constant QUEUE_ROLE = 13;
    uint8 public constant SOLVER_CALLER_ROLE = 14;
    uint256 public depositAmt = 10 ether;
    uint256 public minimumMint = 10 ether;
    EthPerWstEthRateProvider ethPerWstEthRateProvider;

    function setUp() public override {
        super.setUp();
        // Deploy contracts
        solver = new MultiAssetAtomicSolverRedeem(SOLVER_OWNER);
        atomicQueue = new AtomicQueue();

        // TODO: add ezETH and rsETH plus their rate providers and approvals et al
        vm.startPrank(TELLER_OWNER);
        teller.addAsset(WETH);
        teller.addAsset(WSTETH);
        vm.stopPrank();

        // Setup accountant

        ethPerWstEthRateProvider =
            new EthPerWstEthRateProvider(address(ETH_PER_STETH_CHAINLINK), address(WSTETH_ADDRESS), 1 days);
        bool isPeggedToBase = false;

        // Setup mock tokens
        wantToken1 = ERC20(address(new MockERC20("Want Token 1", "WANT1", 18)));
        wantToken2 = ERC20(address(new MockERC20("Want Token 2", "WANT2", 6)));

        // Approve tokens
        wantToken1.approve(address(boringVault), type(uint256).max);
        wantToken2.approve(address(boringVault), type(uint256).max);
        WETH.approve(address(boringVault), type(uint256).max);
        WSTETH.approve(address(boringVault), type(uint256).max);

        vm.prank(SOLVER_OWNER);
        solver.setAuthority(rolesAuthority);
        vm.stopPrank();

        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );

        rolesAuthority.setRoleCapability(
            QUEUE_ROLE, address(solver), MultiAssetAtomicSolverRedeem.finishSolve.selector, true
        );

        rolesAuthority.setRoleCapability(
            SOLVER_CALLER_ROLE, address(solver), MultiAssetAtomicSolverRedeem.multiAssetRedeemSolve.selector, true
        );
        rolesAuthority.setRoleCapability(
            QUEUE_ROLE, address(solver), MultiAssetAtomicSolverRedeem.finishSolve.selector, true
        );

        // Setup roles and permissions
        rolesAuthority.setUserRole(address(solver), SOLVER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicQueue), QUEUE_ROLE, true);
        rolesAuthority.setUserRole(SOLVER_OWNER, SOLVER_CALLER_ROLE, true);

        // Setup teller and accountant
        vm.startPrank(TELLER_OWNER);
        teller.addAsset(offerToken);
        teller.addAsset(wantToken1);
        teller.addAsset(wantToken2);
        vm.stopPrank();

        vm.startPrank(ACCOUNTANT_OWNER);
        accountant.setRateProviderData(
            ERC20(address(WSTETH_ADDRESS)), isPeggedToBase, address(ethPerWstEthRateProvider)
        );
        accountant.setRateProviderData(wantToken1, false, address(new MockRateProvider(1.05e18)));
        accountant.setRateProviderData(wantToken2, false, address(new MockRateProvider(0.000833e18)));
        vm.stopPrank();
    }

    function test_MultiAssetRedeemSolve() public {
        address[] memory users = new address[](3);
        users[0] = makeAddr("user1");
        users[1] = makeAddr("user2");
        users[2] = makeAddr("user3");

        deal(address(WSTETH), address(this), depositAmt);
        teller.deposit(WSTETH, depositAmt, minimumMint);
        boringVault.approve(address(atomicQueue), type(uint256).max);

        // Setup user balances and approvals
        for (uint256 i = 0; i < users.length; i++) {
            deal(address(WSTETH), users[i], depositAmt);
            deal(address(WETH), users[i], depositAmt);
            deal(address(wantToken1), users[i], depositAmt);
            deal(address(wantToken2), users[i], 1e10);
            vm.startPrank(users[i]);
            ERC20(WSTETH).approve(address(atomicQueue), type(uint256).max);
            ERC20(WETH).approve(address(atomicQueue), type(uint256).max);
            ERC20(wantToken1).approve(address(atomicQueue), type(uint256).max);
            ERC20(wantToken2).approve(address(atomicQueue), type(uint256).max);
            vm.stopPrank();
        }

        // user 1 deposits WETH
        vm.startPrank(users[0]);
        console2.log("boring vault, user1 before deposit", boringVault.balanceOf(users[0]));
        WETH.approve(address(boringVault), type(uint256).max);
        teller.deposit(WETH, depositAmt, minimumMint);
        console2.log("boring vault, user1 after deposit", boringVault.balanceOf(users[0]));
        vm.stopPrank();
        // user 2 deposits WantAsset1
        vm.startPrank(users[1]);
        console2.log("boring vault, user2 before deposit", boringVault.balanceOf(users[1]));
        wantToken1.approve(address(boringVault), type(uint256).max);
        teller.deposit(wantToken1, depositAmt, minimumMint);
        console2.log("boring vault, user2 after deposit", boringVault.balanceOf(users[1]));
        vm.stopPrank();
        // user 3 deposits WantAsset2
        vm.startPrank(users[2]);
        console2.log("boring vault, user3 before deposit", boringVault.balanceOf(users[2]));
        WSTETH.approve(address(boringVault), type(uint256).max);
        teller.deposit(WSTETH, 1e18, 1e18);
        console2.log("boring vault, user3 after deposit", boringVault.balanceOf(users[2]));
        vm.stopPrank();

        // set atomic queue requests

        AtomicQueue.AtomicRequest memory request1 = AtomicQueue.AtomicRequest({
            deadline: 2 ** 32,
            atomicPrice: 5 * 10 ** 17, //0.5 per share
            offerAmount: 10 ** 18, //1 share
            inSolve: false
        });

        AtomicQueue.AtomicRequest memory request2 = AtomicQueue.AtomicRequest({
            deadline: 2 ** 32,
            atomicPrice: 10 ** 18, //1
            offerAmount: 10 ** 18, //1 share
            inSolve: false
        });

        AtomicQueue.AtomicRequest memory request3 = AtomicQueue.AtomicRequest({
            deadline: 2 ** 32,
            atomicPrice: 0.8e18, //0.8 per share
            offerAmount: 10 ** 18, //1 share
            inSolve: false
        });

        vm.startPrank(users[0]);
        atomicQueue.updateAtomicRequest(ERC20(boringVault), ERC20(WETH), request1);
        ERC20(boringVault).approve(address(atomicQueue), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(users[1]);
        atomicQueue.updateAtomicRequest(ERC20(boringVault), ERC20(wantToken1), request2);
        ERC20(boringVault).approve(address(atomicQueue), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(users[2]);
        atomicQueue.updateAtomicRequest(ERC20(boringVault), ERC20(WSTETH), request3);
        ERC20(boringVault).approve(address(atomicQueue), type(uint256).max);
        vm.stopPrank();

        // Setup solver balance intially to be 10 of token1 and 3000 of token2
        deal(address(WETH), SOLVER_OWNER, 10e18);
        deal(address(WSTETH), SOLVER_OWNER, 0.4e18);

        address[] memory wantArr1 = new address[](1);
        wantArr1[0] = users[0];
        address[] memory wantArr2 = new address[](1);
        wantArr2[0] = users[2];
        address[] memory wantArr3 = new address[](1);
        wantArr3[0] = users[1];

        MultiAssetAtomicSolverRedeem.WantAssetData[] memory wantAssets =
            new MultiAssetAtomicSolverRedeem.WantAssetData[](3);
        wantAssets[0] = MultiAssetAtomicSolverRedeem.WantAssetData({
            asset: WETH,
            minimumAssetsOut: 0,
            maxAssets: type(uint256).max,
            excessAssetAmount: 0,
            useSolverBalanceFirst: true,
            users: wantArr1
        });
        wantAssets[1] = MultiAssetAtomicSolverRedeem.WantAssetData({
            asset: WSTETH,
            minimumAssetsOut: 0,
            maxAssets: type(uint256).max,
            excessAssetAmount: 0,
            useSolverBalanceFirst: true,
            users: wantArr2
        });
        wantAssets[2] = MultiAssetAtomicSolverRedeem.WantAssetData({
            asset: wantToken1,
            minimumAssetsOut: 0,
            maxAssets: type(uint256).max,
            excessAssetAmount: 0.3e18,
            useSolverBalanceFirst: false,
            users: wantArr3
        });

        uint256 solverBalancePreWeth = WETH.balanceOf(SOLVER_OWNER);
        uint256 solverBalancePreWsteth = WSTETH.balanceOf(SOLVER_OWNER);
        uint256 solverBalancePreWantToken1 = wantToken1.balanceOf(SOLVER_OWNER);
        uint256 solverBalancePreBoringVault = boringVault.balanceOf(SOLVER_OWNER);
        uint256 wethUserBalancePre = WETH.balanceOf(users[0]);
        uint256 wstethBalancePre = WSTETH.balanceOf(users[2]);
        uint256 wantToken1BalancePre = wantToken1.balanceOf(users[1]);
        uint256 boringVaultPreSupply = boringVault.totalSupply();
        vm.startPrank(SOLVER_OWNER);
        WETH.approve(address(solver), type(uint256).max);
        WSTETH.approve(address(solver), type(uint256).max);
        wantToken1.approve(address(solver), type(uint256).max);
        solver.multiAssetRedeemSolve(
            IAtomicQueue(address(atomicQueue)), boringVault, wantAssets, teller, -1 * int256(1e18), address(0)
        );
        vm.stopPrank();

        uint256 solverBalancePostWeth = WETH.balanceOf(SOLVER_OWNER);
        uint256 solverBalancePostWsteth = WSTETH.balanceOf(SOLVER_OWNER);
        uint256 solverBalancePostWantToken1 = wantToken1.balanceOf(SOLVER_OWNER);
        uint256 solverBalancePostBoringVault = boringVault.balanceOf(SOLVER_OWNER);

        // should use solver balance first for weth
        //there was 1 token request for 0.5 WETH and 1 token request for 0.8 WSTETH
        //solver should has 10 WETH and 0.4 WSTETH before the solve
        // therefore the entire weth order should be filled by solver balance and half of the WSTETH order should be
        // filled by solver balance
        // this means afterwards that solver balance will be 9.5 WETH and 0 WSTETH
        // since an excess of 0.3 wantToken1 was requested, and solver had 0 wantToken1 to start, final balance of
        // solver should be 0.3 wantToken1
        // then there should be a residual of offer shares left with solver since address(0) was passed as the
        // redeemCurrency

        assertEq(solverBalancePreWeth - solverBalancePostWeth, request1.atomicPrice, "Solver should have spent WETH");
        assertEq(
            solverBalancePreWsteth - solverBalancePostWsteth,
            request3.atomicPrice / 2,
            "Solver should have spent WSTETH"
        );
        assertEq(
            solverBalancePostWantToken1 - solverBalancePreWantToken1,
            wantAssets[2].excessAssetAmount,
            "Solver should have received excess wantToken1"
        );
        assertGt(
            solverBalancePostBoringVault, solverBalancePreBoringVault, "Solver should have received residual shares"
        );

        //users should have received their assets
        // user 1 should have received 0.5 WETH for 1 share
        // user 2 should have received 0.8 WSTETH for 1 share
        // user 3 should have received 1 wantToken1 for 1 share
        // the total supply should went down 3 - balance change for solver owner
        assertEq(WETH.balanceOf(users[0]) - wethUserBalancePre, request1.atomicPrice, "user 1 got an increase of WETH");
        assertEq(
            WSTETH.balanceOf(users[2]) - wstethBalancePre, request3.atomicPrice, "user 2 got an increase of WSTETH"
        );
        assertEq(
            wantToken1.balanceOf(users[1]) - wantToken1BalancePre,
            request2.atomicPrice,
            "user 3 got an increase of wantToken1"
        );
        assertEq(
            boringVaultPreSupply - boringVault.totalSupply(),
            request1.offerAmount + request2.offerAmount + request3.offerAmount + solverBalancePreBoringVault
                - solverBalancePostBoringVault,
            "total supply should have decreased by the sum of the offer amounts minus the solver balance change"
        );
    }

    function test_FinishSolve() public {
        // Setup
        address initiator = address(solver);
        uint256 offerReceived = 100e18;
        uint256 wantApprovalAmount = 90e18;

        bytes memory runData =
            abi.encode(MultiAssetAtomicSolverRedeem.SolveType.REDEEM, address(this), 85e18, 100e18, teller, 1e18);

        vm.prank(SOLVER_OWNER);
        wantToken1.approve(address(solver), type(uint256).max);

        vm.prank(address(atomicQueue));
        solver.finishSolve(runData, initiator, boringVault, wantToken1, offerReceived, wantApprovalAmount);

        // Assert results
        assertEq(
            wantToken1.allowance(address(solver), address(atomicQueue)),
            wantApprovalAmount,
            "Solver should approve queue to spend wantToken1"
        );
    }

    function testFail_FinishSolve_WrongInitiator() public {
        bytes memory runData =
            abi.encode(MultiAssetAtomicSolverRedeem.SolveType.REDEEM, address(this), 85e18, 100e18, teller, 1e18);

        vm.prank(address(atomicQueue));
        solver.finishSolve(
            runData,
            address(0x999), // Wrong initiator
            boringVault,
            wantToken1,
            100e18,
            90e18
        );
    }

    function testFail_FinishSolve_MaxAssetsExceeded() public {
        bytes memory runData =
            abi.encode(MultiAssetAtomicSolverRedeem.SolveType.REDEEM, address(this), 85e18, 100e18, teller, 1e18);

        vm.prank(address(atomicQueue));
        solver.finishSolve(
            runData,
            address(solver),
            boringVault,
            wantToken1,
            100e18,
            101e18 // Exceeds maxAssets
        );
    }

    function test_GlobalSlippageCheck() public {
        MultiAssetAtomicSolverRedeem.WantAssetData[] memory wantAssets =
            new MultiAssetAtomicSolverRedeem.WantAssetData[](2);
        wantAssets[0] = MultiAssetAtomicSolverRedeem.WantAssetData({
            asset: wantToken1,
            minimumAssetsOut: 90e18,
            maxAssets: 100e18,
            excessAssetAmount: 5e18,
            useSolverBalanceFirst: true,
            users: new address[](0)
        });
        wantAssets[1] = MultiAssetAtomicSolverRedeem.WantAssetData({
            asset: wantToken2,
            minimumAssetsOut: 45e6,
            maxAssets: 50e6,
            excessAssetAmount: 2e6,
            useSolverBalanceFirst: false,
            users: new address[](0)
        });

        vm.prank(SOLVER_OWNER);
        vm.expectRevert(
            // abi.encodeWithSelector(
            //     MultiAssetAtomicSolverRedeem.MultiAssetAtomicSolverRedeem___GlobalSlippageThresholdExceeded.selector,
            //     0,
            //     0,
            //     0
            // )
        );
        solver.multiAssetRedeemSolve(
            IAtomicQueue(address(atomicQueue)),
            boringVault,
            wantAssets,
            teller,
            int256(1e19), // Very high slippage threshold, should fail,
            address(WETH)
        );
    }
}

// Mock contracts for testing
contract MockAtomicQueue is IAtomicQueue {
    function solve(
        ERC20 offer,
        ERC20 want,
        address[] calldata users,
        bytes calldata runData,
        address solver
    )
        external
        override
    {
        // Mock implementation
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol, decimals) { }
}

contract MockRateProvider {
    uint256 public rate;

    constructor(uint256 _rate) {
        rate = _rate;
    }

    function getRate() external view returns (uint256) {
        return rate;
    }
}
