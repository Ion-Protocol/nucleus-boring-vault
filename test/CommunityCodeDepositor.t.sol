// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { TellerWithMultiAssetSupportTest } from "./TellerWithMultiAssetSupport.t.sol";
import { CommunityCodeDepositor } from "src/helper/CommunityCodeDepositor.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { console } from "forge-std/console.sol";

/**
 * Test is done on Hyperliquid since most CommunityCodeDepositors will live on
 * HL.
 */
contract CommunityCodeDepositorTest is TellerWithMultiAssetSupportTest {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    CommunityCodeDepositor public communityCodeDepositor;
    address public to;
    bytes public communityCode;

    ERC20 public NATIVE_WRAPPER = WETH;

    function setUp() public override {
        super.setUp();

        // Deploy CommunityCodeDepositor
        communityCodeDepositor = new CommunityCodeDepositor(address(teller), address(this), address(NATIVE_WRAPPER));

        // Setup test recipient
        to = makeAddr("recipient");

        // Setup test community code
        communityCode = abi.encode("test-community-code");
    }

    function testDeposit() public {
        uint256 depositAmount = 1e18;
        uint256 minimumMint = 0;

        deal(address(NATIVE_WRAPPER), address(this), depositAmount);

        NATIVE_WRAPPER.approve(address(communityCodeDepositor), depositAmount);

        uint256 initialNativeWrapperBalance = NATIVE_WRAPPER.balanceOf(address(this));
        uint256 initialToBalance = boringVault.balanceOf(to);

        // Perform deposit
        uint256 shares = communityCodeDepositor.deposit(WETH, depositAmount, minimumMint, to, communityCode);

        require(shares == depositAmount, "Shares minted should equal deposit amount for 1:1 asset");

        // Verify balances
        assertEq(
            NATIVE_WRAPPER.balanceOf(address(this)),
            initialNativeWrapperBalance - depositAmount,
            "WETH balance not decreased"
        );
        assertEq(boringVault.balanceOf(to), initialToBalance + shares, "BoringVault shares not received");
        assertEq(shares, depositAmount, "Shares minted should equal deposit amount for 1:1 asset");
    }

    function testDepositNative() public {
        // Setup test parameters
        uint256 depositAmount = 1e18;
        uint256 minimumMint = 0;

        // Record initial balances
        uint256 initialToBalance = boringVault.balanceOf(to);

        // Perform native deposit
        uint256 shares =
            communityCodeDepositor.depositNative{ value: depositAmount }(depositAmount, minimumMint, to, communityCode);

        require(shares == depositAmount, "Shares minted should equal deposit amount for 1:1 asset");

        // Verify balances
        assertEq(boringVault.balanceOf(to), initialToBalance + shares, "BoringVault shares not received");
        assertEq(shares, depositAmount, "Shares minted should equal deposit amount for 1:1 asset");
    }
}
