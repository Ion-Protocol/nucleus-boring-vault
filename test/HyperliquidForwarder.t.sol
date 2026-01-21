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
import { HyperliquidForwarder } from "src/helper/HyperliquidForwarder.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

contract HyperliquidForwarderTest is Test, MainnetAddresses {

    HyperliquidForwarder forwarder;
    address WHYPE = 0x5555555555555555555555555555555555555555;
    address PURR = 0x9b498C3c8A0b8CD8BA1D9851d40D186F1872b44E;
    uint16 PURRID = 1;
    address PURRBridge = 0x2000000000000000000000000000000000000001;

    address owner;
    address hyperliquidMultisig1;
    address hyperliquidMultisig2;

    function setUp() external {
        uint256 forkId = vm.createFork(vm.envString("HL_RPC_URL"));
        vm.selectFork(forkId);

        owner = makeAddr("owner");
        hyperliquidMultisig1 = makeAddr("1");
        hyperliquidMultisig2 = makeAddr("2");

        forwarder = new HyperliquidForwarder(owner);

        vm.startPrank(owner);
        forwarder.addTokenIDToBridgeMapping(PURR, PURRBridge, PURRID);
        forwarder.setEOAAllowStatus(hyperliquidMultisig1, true);
        vm.stopPrank();

        vm.startPrank(hyperliquidMultisig1);
        ERC20(WHYPE).approve(address(forwarder), type(uint256).max);
        ERC20(PURR).approve(address(forwarder), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(hyperliquidMultisig2);
        ERC20(WHYPE).approve(address(forwarder), type(uint256).max);
        ERC20(PURR).approve(address(forwarder), type(uint256).max);
        vm.stopPrank();
    }

    function testCannotAddIncorrectBridge() external {
        vm.startPrank(owner);
        vm.expectRevert(HyperliquidForwarder.HyperliquidForwarder__BridgeAddressDoesNotMatchTokenID.selector);
        forwarder.addTokenIDToBridgeMapping(PURR, PURRBridge, 77);
        vm.stopPrank();
    }

    function testForward() external {
        // setup
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        deal(WHYPE, user1, 1e18);
        deal(PURR, user1, 1e18);
        deal(WHYPE, user2, 1e18);
        deal(PURR, user2, 1e18);

        // approve sender1
        vm.prank(owner);
        forwarder.setSenderAllowStatus(user1, true);

        // test user1, happy path
        vm.startPrank(user1);
        ERC20(WHYPE).approve(address(forwarder), type(uint256).max);
        ERC20(PURR).approve(address(forwarder), type(uint256).max);

        uint256 whypeBalBefore = ERC20(WHYPE).balanceOf(0x2222222222222222222222222222222222222222);
        uint256 purrBalBefore = ERC20(PURR).balanceOf(PURRBridge);

        forwarder.forward(ERC20(WHYPE), 0.2e18, hyperliquidMultisig1);
        assertEq(ERC20(WHYPE).balanceOf(0x2222222222222222222222222222222222222222) - whypeBalBefore, 0.2e18);

        forwarder.forward(ERC20(PURR), 0.3e18, hyperliquidMultisig1);
        assertEq(ERC20(PURR).balanceOf(PURRBridge) - purrBalBefore, 0.3e18);
        vm.stopPrank();

        // now we start on user2, the unhappy path
        //
        // user2 is not approved to send WHYPE as a sender
        vm.startPrank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(HyperliquidForwarder.HyperliquidForwarder__SenderNotAllowed.selector, user2)
        );
        forwarder.forward(ERC20(WHYPE), 0.2e18, hyperliquidMultisig1);
        vm.stopPrank();

        // owner removes purr support and gives user2 approval
        vm.startPrank(owner);
        forwarder.addTokenIDToBridgeMapping(PURR, address(0), PURRID);
        forwarder.setSenderAllowStatus(user2, true);
        vm.stopPrank();

        // now user fails to forward purr
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(HyperliquidForwarder.HyperliquidForwarder__BridgeNotSet.selector, PURR));
        forwarder.forward(ERC20(PURR), 0.3e18, hyperliquidMultisig1);
        vm.stopPrank();

        // Owner returns purr to allowlist but user wants to send to multisig2
        vm.prank(owner);
        forwarder.addTokenIDToBridgeMapping(PURR, PURRBridge, PURRID);

        vm.startPrank(user2);
        ERC20(WHYPE).approve(address(forwarder), type(uint256).max);
        ERC20(PURR).approve(address(forwarder), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                HyperliquidForwarder.HyperliquidForwarder__EOANotAllowed.selector, hyperliquidMultisig2
            )
        );
        forwarder.forward(ERC20(PURR), 0.3e18, hyperliquidMultisig2);
        vm.stopPrank();

        // Owner allows multisig2 and user2 can finally bridge
        vm.prank(owner);
        forwarder.setEOAAllowStatus(hyperliquidMultisig2, true);
        vm.prank(user2);
        forwarder.forward(ERC20(PURR), 0.25e18, hyperliquidMultisig2);
        assertEq(ERC20(PURR).balanceOf(PURRBridge) - purrBalBefore, 0.55e18);
        vm.stopPrank();
    }

}
