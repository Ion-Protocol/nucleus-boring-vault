// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {
    MultiAssetAtomicSolverRedeem,
    IAtomicQueue
} from "./../../src/atomic-queue/multi-asset-solvers/MultiAssetAtomicSolverRedeem.sol";
import { TellerWithMultiAssetSupport } from "./../../src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "./../../src/base/Roles/AccountantWithRateProviders.sol";
import { BoringVault } from "./../../src/base/BoringVault.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { console2 } from "forge-std/console2.sol";

contract MultiAssetAtomicSolverRedeemTest is StdUtils {
    using FixedPointMathLib for uint256;

    MultiAssetAtomicSolverRedeem public solver;
    IAtomicQueue public atomicQueue;
    TellerWithMultiAssetSupport public teller;
    AccountantWithRateProviders public accountant;
    BoringVault public boringVault;
    RolesAuthority public rolesAuthority;

    ERC20 public offerToken;
    ERC20 public wantToken1;
    ERC20 public wantToken2;

    address public constant SOLVER_OWNER = address(0x1);
    address public constant TELLER_OWNER = address(0x2);
    address public constant ACCOUNTANT_OWNER = address(0x3);
    uint8 public constant SOLVER_ROLE = 1;
    uint8 public constant QUEUE_ROLE = 2;

    function setUp() public {
        // Deploy contracts
        solver = new MultiAssetAtomicSolverRedeem(SOLVER_OWNER);
        atomicQueue = IAtomicQueue(address(new MockAtomicQueue()));
        teller = new TellerWithMultiAssetSupport(TELLER_OWNER);
        accountant = new AccountantWithRateProviders(ACCOUNTANT_OWNER);
        boringVault = new BoringVault();
        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));

        // Setup mock tokens
        offerToken = new MockERC20("Offer Token", "OFFER", 18);
        wantToken1 = new MockERC20("Want Token 1", "WANT1", 18);
        wantToken2 = new MockERC20("Want Token 2", "WANT2", 6);

        // Setup roles and permissions
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setRoleCapability(
            QUEUE_ROLE, address(solver), MultiAssetAtomicSolverRedeem.finishSolve.selector, true
        );
        rolesAuthority.setUserRole(address(solver), SOLVER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicQueue), QUEUE_ROLE, true);

        // Setup teller and accountant
        vm.startPrank(TELLER_OWNER);
        teller.addAsset(offerToken);
        teller.addAsset(wantToken1);
        teller.addAsset(wantToken2);
        vm.stopPrank();

        vm.startPrank(ACCOUNTANT_OWNER);
        accountant.setRateProviderData(wantToken1, false, address(new MockRateProvider(1e18)));
        accountant.setRateProviderData(wantToken2, false, address(new MockRateProvider(2e18)));
        vm.stopPrank();

        // Approve tokens
        offerToken.approve(address(boringVault), type(uint256).max);
        wantToken1.approve(address(boringVault), type(uint256).max);
        wantToken2.approve(address(boringVault), type(uint256).max);
    }

    function test_MultiAssetRedeemSolve() public {
        address[] memory users = new address[](3);
        users[0] = address(0x100);
        users[1] = address(0x101);
        users[2] = address(0x102);

        // Setup user balances and approvals
        for (uint256 i = 0; i < users.length; i++) {
            offerToken.mint(users[i], 100e18);
            vm.prank(users[i]);
            offerToken.approve(address(atomicQueue), type(uint256).max);
        }

        // Setup solver balance
        wantToken1.mint(SOLVER_OWNER, 1000e18);
        wantToken2.mint(SOLVER_OWNER, 1000e6);

        MultiAssetAtomicSolverRedeem.WantAssetData[] memory wantAssets =
            new MultiAssetAtomicSolverRedeem.WantAssetData[](2);
        wantAssets[0] = MultiAssetAtomicSolverRedeem.WantAssetData({
            asset: wantToken1,
            minimumAssetsOut: 90e18,
            maxAssets: 100e18,
            excessAssetAmount: 5e18,
            useSolverBalanceFirst: true,
            useAsRedeemTokenForExcessOffer: false,
            users: users
        });
        wantAssets[1] = MultiAssetAtomicSolverRedeem.WantAssetData({
            asset: wantToken2,
            minimumAssetsOut: 45e6,
            maxAssets: 50e6,
            excessAssetAmount: 2e6,
            useSolverBalanceFirst: false,
            useAsRedeemTokenForExcessOffer: true,
            users: users
        });

        vm.prank(SOLVER_OWNER);
        solver.multiAssetRedeemSolve(atomicQueue, offerToken, wantAssets, 150e18, teller, int256(1e17));

        // Assert results
        for (uint256 i = 0; i < users.length; i++) {
            assertGt(wantToken1.balanceOf(users[i]), 0, "User should have received wantToken1");
            assertGt(wantToken2.balanceOf(users[i]), 0, "User should have received wantToken2");
        }

        assertLt(wantToken1.balanceOf(SOLVER_OWNER), 1000e18, "Solver should have spent wantToken1");
        assertLt(wantToken2.balanceOf(SOLVER_OWNER), 1000e6, "Solver should have spent wantToken2");
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
        solver.finishSolve(runData, initiator, offerToken, wantToken1, offerReceived, wantApprovalAmount);

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
            offerToken,
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
            offerToken,
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
            useAsRedeemTokenForExcessOffer: false,
            users: new address[](0)
        });
        wantAssets[1] = MultiAssetAtomicSolverRedeem.WantAssetData({
            asset: wantToken2,
            minimumAssetsOut: 45e6,
            maxAssets: 50e6,
            excessAssetAmount: 2e6,
            useSolverBalanceFirst: false,
            useAsRedeemTokenForExcessOffer: true,
            users: new address[](0)
        });

        vm.prank(SOLVER_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultiAssetAtomicSolverRedeem.MultiAssetAtomicSolverRedeem___GlobalSlippageThresholdExceeded.selector,
                0,
                0,
                0
            )
        );
        solver.multiAssetRedeemSolve(
            atomicQueue,
            offerToken,
            wantAssets,
            150e18,
            teller,
            int256(1e19) // Very high slippage threshold, should fail
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

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
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
