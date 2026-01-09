// SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { Pauser } from "src/helper/Pauser.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";

contract PauserTest is Test, MainnetAddresses {

    event Pauser__FailedPause(address toPause, bytes response);
    event Pauser__EmptySymbol(string symbol);

    uint8 internal constant PAUSER_ROLE = 5;

    // State variables for deployed contracts
    Pauser internal pauser;

    BoringVault internal b1;
    AccountantWithRateProviders internal a1;
    ManagerWithMerkleVerification internal m1;
    RolesAuthority internal r1;
    TellerWithMultiAssetSupport internal t1;

    BoringVault internal b2;
    AccountantWithRateProviders internal a2;
    ManagerWithMerkleVerification internal m2;
    RolesAuthority internal r2;
    TellerWithMultiAssetSupport internal t2;

    BoringVault internal b3;
    AccountantWithRateProviders internal a3;
    ManagerWithMerkleVerification internal m3;
    RolesAuthority internal r3;
    TellerWithMultiAssetSupport internal t3;

    function setUp() external {
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19_363_419;
        _startFork(rpcKey, blockNumber);

        address[] memory emptyPausers = new address[](0);

        // Initialize state variables
        pauser = new Pauser(address(this), emptyPausers);

        // Deploy 1 "vault" with symbol BV1
        r1 = new RolesAuthority(address(this), Authority(address(0))); // Specific authority for vault 1

        b1 = new BoringVault(address(this), "Boring Vault 1", "BV1", 18);
        b1.setAuthority(r1);

        a1 = new AccountantWithRateProviders(
            address(this), address(b1), address(this), 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0, 0
        );
        a1.setAuthority(r1);

        m1 = new ManagerWithMerkleVerification(address(this), address(b1), vault);
        m1.setAuthority(r1);

        t1 = new TellerWithMultiAssetSupport(address(this), address(b1), address(a1));
        t1.setAuthority(r1);

        r1.setUserRole(address(pauser), PAUSER_ROLE, true);
        r1.setRoleCapability(PAUSER_ROLE, address(a1), AccountantWithRateProviders.pause.selector, true);
        r1.setRoleCapability(PAUSER_ROLE, address(m1), ManagerWithMerkleVerification.pause.selector, true);
        r1.setRoleCapability(PAUSER_ROLE, address(t1), TellerWithMultiAssetSupport.pause.selector, true);

        pauser.addContract(address(a1), "BV1");
        pauser.addContract(address(m1), "BV1");
        pauser.addContract(address(t1), "BV1");

        // Deploy 2 "vault" with symbol BV2
        r2 = new RolesAuthority(address(this), Authority(address(0))); // Specific authority for vault 2

        b2 = new BoringVault(address(this), "Boring Vault 2", "BV2", 18);
        b2.setAuthority(r2);

        a2 = new AccountantWithRateProviders(
            address(this), address(b2), address(this), 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0, 0
        );
        a2.setAuthority(r2);

        m2 = new ManagerWithMerkleVerification(address(this), address(b2), vault);
        m2.setAuthority(r2);

        t2 = new TellerWithMultiAssetSupport(address(this), address(b2), address(a2));
        t2.setAuthority(r2);

        r2.setUserRole(address(pauser), PAUSER_ROLE, true);
        r2.setRoleCapability(PAUSER_ROLE, address(a2), AccountantWithRateProviders.pause.selector, true);
        r2.setRoleCapability(PAUSER_ROLE, address(m2), ManagerWithMerkleVerification.pause.selector, true);
        r2.setRoleCapability(PAUSER_ROLE, address(t2), TellerWithMultiAssetSupport.pause.selector, true);

        pauser.addContract(address(a2), "BV2");
        pauser.addContract(address(m2), "BV2");
        pauser.addContract(address(t2), "BV2");

        // Deploy 3 "vault" with symbol BV3
        r3 = new RolesAuthority(address(this), Authority(address(0))); // Specific authority for vault 3
        b3 = new BoringVault(address(this), "Boring Vault 3", "BV3", 18);
        b3.setAuthority(r3);

        a3 = new AccountantWithRateProviders(
            address(this), address(b3), address(this), 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0, 0
        );
        a3.setAuthority(r3);

        m3 = new ManagerWithMerkleVerification(address(this), address(b3), vault);
        m3.setAuthority(r3);

        t3 = new TellerWithMultiAssetSupport(address(this), address(b3), address(a3));
        t3.setAuthority(r3);

        r3.setUserRole(address(pauser), PAUSER_ROLE, true);
        r3.setRoleCapability(PAUSER_ROLE, address(a3), AccountantWithRateProviders.pause.selector, true);
        r3.setRoleCapability(PAUSER_ROLE, address(m3), ManagerWithMerkleVerification.pause.selector, true);
        r3.setRoleCapability(PAUSER_ROLE, address(t3), TellerWithMultiAssetSupport.pause.selector, true);

        pauser.addContract(address(a3), "BV3");
        pauser.addContract(address(m3), "BV3");
        pauser.addContract(address(t3), "BV3");
    }

    function testPauseAll() external {
        uint256 failCount = pauser.pauseAll();
        assertEq(failCount, 0);

        (,,,,,,,, bool isPaused,,,) = a1.accountantState();
        assertTrue(isPaused);
        assertTrue(m1.isPaused());
        assertTrue(t1.isPaused());

        (,,,,,,,, isPaused,,,) = a2.accountantState();
        assertTrue(isPaused);
        assertTrue(m2.isPaused());
        assertTrue(t2.isPaused());

        (,,,,,,,, isPaused,,,) = a3.accountantState();
        assertTrue(isPaused);
        assertTrue(m3.isPaused());
        assertTrue(t3.isPaused());
    }

    function testPauseAllSymbol() external {
        uint256 failCount = pauser.pauseSymbol("BV1");
        assertEq(failCount, 0);

        (,,,,,,,, bool isPaused,,,) = a1.accountantState();
        assertTrue(isPaused);
        assertTrue(m1.isPaused());
        assertTrue(t1.isPaused());

        (,,,,,,,, isPaused,,,) = a2.accountantState();
        assertTrue(!isPaused);
        assertTrue(!m2.isPaused());
        assertTrue(!t2.isPaused());

        (,,,,,,,, isPaused,,,) = a3.accountantState();
        assertTrue(!isPaused);
        assertTrue(!m3.isPaused());
        assertTrue(!t3.isPaused());
    }

    function testPauseSingleIndex() external {
        pauser.pauseSingle("BV1", 2);

        (,,,,,,,, bool isPaused,,,) = a1.accountantState();
        assertTrue(!isPaused);
        assertTrue(!m1.isPaused());
        assertTrue(t1.isPaused());

        (,,,,,,,, isPaused,,,) = a2.accountantState();
        assertTrue(!isPaused);
        assertTrue(!m2.isPaused());
        assertTrue(!t2.isPaused());

        (,,,,,,,, isPaused,,,) = a3.accountantState();
        assertTrue(!isPaused);
        assertTrue(!m3.isPaused());
        assertTrue(!t3.isPaused());
    }

    function testPauseSingleByContract() external {
        pauser.pauseSingle(address(m1));

        (,,,,,,,, bool isPaused,,,) = a1.accountantState();
        assertTrue(!isPaused);
        assertTrue(m1.isPaused());
        assertTrue(!t1.isPaused());

        (,,,,,,,, isPaused,,,) = a2.accountantState();
        assertTrue(!isPaused);
        assertTrue(!m2.isPaused());
        assertTrue(!t2.isPaused());

        (,,,,,,,, isPaused,,,) = a3.accountantState();
        assertTrue(!isPaused);
        assertTrue(!m3.isPaused());
        assertTrue(!t3.isPaused());
    }

    function testHandlesFailures() external {
        vm.expectEmit();
        emit Pauser__FailedPause(address(b1), hex"");
        pauser.pauseSingle(address(b1));

        r1.setUserRole(address(pauser), PAUSER_ROLE, false);
        vm.expectEmit();
        emit Pauser__FailedPause(
            address(m1),
            hex"08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000c554e415554484f52495a45440000000000000000000000000000000000000000"
        );
        pauser.pauseSingle(address(m1));
    }

    function testPauseAllSucceedsEvenWithNonsenseContractsAdded() external {
        pauser.addContract(address(b1), "BV1");
        pauser.addContract(address(b1), "NOT A SYMBOL :P");
        pauser.addContract(address(0), "BV2");
        pauser.addContract(address(0), "wacky");

        uint256 failingCount = pauser.pauseAll();
        assertEq(failingCount, 4);

        (,,,,,,,, bool isPaused,,,) = a1.accountantState();
        assertTrue(isPaused);
        assertTrue(m1.isPaused());
        assertTrue(t1.isPaused());

        (,,,,,,,, isPaused,,,) = a2.accountantState();
        assertTrue(isPaused);
        assertTrue(m2.isPaused());
        assertTrue(t2.isPaused());

        (,,,,,,,, isPaused,,,) = a3.accountantState();
        assertTrue(isPaused);
        assertTrue(m3.isPaused());
        assertTrue(t3.isPaused());
    }

    function testResponseWhenPausingNonexistentSymbol() external {
        vm.expectEmit();
        emit Pauser__EmptySymbol("NONEXISTENT SYMBOL");
        pauser.pauseSymbol("NONEXISTENT SYMBOL");
    }

    function testAuth() external {
        vm.prank(address(1009));
        vm.expectRevert(abi.encodeWithSelector(Pauser.Pauser__Unauthorized.selector));
        pauser.pauseAll();

        address[] memory a = new address[](1);
        a[0] = address(1009);
        pauser.addApprovedPausers(a);
        vm.prank(address(1009));
        pauser.pauseAll();
        assertTrue(m1.isPaused());

        pauser.removeApprovedPausers(a);

        vm.prank(address(1009));
        vm.expectRevert(abi.encodeWithSelector(Pauser.Pauser__Unauthorized.selector));
        pauser.pauseAll();
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }

}
