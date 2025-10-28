// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { VaultArchitectureSharedSetup } from "test/shared-setup/VaultArchitectureSharedSetup.t.sol";
import { CommunityCodeDepositor, INativeWrapper } from "src/helper/CommunityCodeDepositor.sol";
import { stdStorage, StdStorage, stdError } from "@forge-std/Test.sol";
import { console } from "forge-std/console.sol";

interface IERC2612 {
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);
}

contract CommunityCodeDepositorWithoutNativeTest is VaultArchitectureSharedSetup {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    CommunityCodeDepositor public communityCodeDepositor;
    address public owner = vm.addr(uint256(bytes32("owner")));

    function setUp() external {
        // Setup forked environment
        string memory rpcKey = "MAINNET_RPC_URL";
        // block at 10/21/2025
        uint256 blockNumber = 23_628_127;
        _startFork(rpcKey, blockNumber);

        // Set up default depositable assets
        address[] memory assets = new address[](1);
        assets[0] = address(USDC);

        uint256 startingExchangeRate = 1e6;

        // Deploy vault architecture using the helper function
        (boringVault, teller, accountant) =
            _deployVaultArchitecture("Stablecoin Earn", "earnUSDC", 6, address(USDC), assets, startingExchangeRate);

        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        INativeWrapper nativeWrapper = INativeWrapper(WETH);

        // deploy community code depositor
        communityCodeDepositor = new CommunityCodeDepositor(teller, INativeWrapper(address(0)), owner);

        vm.prank(owner);
        communityCodeDepositor.setAuthority(rolesAuthority);

        vm.startPrank(rolesAuthority.owner());
        rolesAuthority.setPublicCapability(
            address(communityCodeDepositor), communityCodeDepositor.deposit.selector, true
        );
        rolesAuthority.setPublicCapability(
            address(communityCodeDepositor), communityCodeDepositor.depositWithPermit.selector, true
        );
        vm.stopPrank();
    }

    // function test_depositNativeWithSenderAsRecipient() external {
    // }

    // function test_depositNativeWithCustomRecipient() external {}

    function test_depositWithSenderAsRecipient() external {
        uint256 depositAmount = 100e6;
        uint256 minimumMint = 100e6;
        address recipient = address(this);

        // expected shares calculation
        console.log("base", address(accountant.base()));
        console.log(accountant.getRate());
        uint256 quoteRate = accountant.getRateInQuoteSafe(ERC20(address(USDC))); // quote / share
        console.log("%d", quoteRate);

        // 100e6 * 1e6 / 1e6
        uint256 expectedShares = depositAmount.mulDivDown(ONE_SHARE, quoteRate);

        _setERC20Balance(address(USDC), address(this), depositAmount);

        USDC.approve(address(communityCodeDepositor), depositAmount);

        uint256 sharesMinted =
            communityCodeDepositor.deposit(ERC20(address(USDC)), depositAmount, minimumMint, recipient, "test code");

        assertEq(USDC.balanceOf(owner), 0, "owner must have no deposit asset balance");
        assertEq(sharesMinted, expectedShares, "shares minted must equal expected shares");
        assertEq(
            ERC20(address(boringVault)).balanceOf(recipient), expectedShares, "recipient must have expected shares"
        );
        assertEq(USDC.balanceOf(address(boringVault)), depositAmount, "boring vault must have deposit asset custody");
    }

    function test_depositWithCustomRecipient() external {
        uint256 depositAmount = 123e6;
        uint256 minimumMint = 123e6;
        address recipient = vm.addr(uint256(bytes32("owner")));

        // expected shares calculation
        uint256 quoteRate = accountant.getRateInQuoteSafe(ERC20(address(USDC))); // quote / share
        uint256 expectedShares = depositAmount.mulDivDown(ONE_SHARE, quoteRate);

        _setERC20Balance(address(USDC), address(this), depositAmount);

        USDC.approve(address(communityCodeDepositor), depositAmount);

        uint256 sharesMinted =
            communityCodeDepositor.deposit(ERC20(address(USDC)), depositAmount, minimumMint, recipient, "test code");

        assertEq(USDC.balanceOf(owner), 0, "owner must have no deposit asset balance");
        assertEq(sharesMinted, expectedShares, "shares minted must equal expected shares");
        assertEq(
            ERC20(address(boringVault)).balanceOf(recipient), expectedShares, "recipient must have expected shares"
        );
        assertEq(USDC.balanceOf(address(boringVault)), depositAmount, "boring vault must have deposit asset custody");
    }

    function test_depositWithPermitWithSenderAsRecipient() external {
        uint256 depositAmount = 123e6;
        uint256 minimumMint = 123e6;

        uint256 deadline = block.timestamp + 1000;

        address spender = address(communityCodeDepositor);

        uint256 quoteRate = accountant.getRateInQuoteSafe(ERC20(address(USDC))); // quote / share
        uint256 expectedShares = depositAmount.mulDivDown(ONE_SHARE, quoteRate);

        // owner is the depositor aka msg.sender to the depositor contract
        uint256 ownerSk = uint256(bytes32("owner_private_key"));
        address owner = vm.addr(ownerSk);

        _setERC20Balance(address(USDC), owner, depositAmount);

        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(IERC2612(address(USDC)), owner, ownerSk, spender, depositAmount, deadline);

        // deposit without approval
        vm.startPrank(owner);
        uint256 sharesMinted = communityCodeDepositor.depositWithPermit(
            ERC20(address(USDC)), depositAmount, minimumMint, owner, "test code", deadline, v, r, s
        );
        vm.stopPrank();

        assertEq(USDC.balanceOf(owner), 0, "owner must have no deposit asset balance");
        assertEq(sharesMinted, expectedShares, "shares minted must equal expected shares");
        assertEq(ERC20(address(boringVault)).balanceOf(owner), expectedShares, "recipient must have expected shares");
        assertEq(USDC.balanceOf(address(boringVault)), depositAmount, "boring vault must have deposit asset custody");
    }

    function test_depositWithPermitWithCustomRecipient() external {
        uint256 depositAmount = 123e6;
        uint256 deadline = block.timestamp + 1000;

        address spender = address(communityCodeDepositor);

        uint256 quoteRate = accountant.getRateInQuoteSafe(ERC20(address(USDC))); // quote / share

        // owner is the depositor aka msg.sender to the depositor contract
        uint256 ownerSk = uint256(bytes32("owner_private_key"));
        address owner = vm.addr(ownerSk);

        address customRecipient = vm.addr(uint256(bytes32("custom_recipient")));

        _setERC20Balance(address(USDC), owner, depositAmount);

        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(IERC2612(address(USDC)), owner, ownerSk, spender, depositAmount, deadline);

        // deposit without approval
        vm.startPrank(owner);
        uint256 sharesMinted = communityCodeDepositor.depositWithPermit(
            ERC20(address(USDC)), depositAmount, depositAmount, customRecipient, "test code", deadline, v, r, s
        );
        vm.stopPrank();

        uint256 expectedShares = depositAmount.mulDivDown(ONE_SHARE, quoteRate);

        assertEq(USDC.balanceOf(owner), 0, "owner must have no deposit asset balance");
        assertEq(boringVault.balanceOf(owner), 0, "owner must have no shares");

        assertEq(sharesMinted, expectedShares, "shares minted must equal expected shares");
        assertEq(boringVault.balanceOf(customRecipient), expectedShares, "recipient must have expected shares");
        assertEq(USDC.balanceOf(address(boringVault)), depositAmount, "boring vault must have deposit asset custody");
    }

    function test_depositWithPermitWithIncorrectSignature() external {
        uint256 depositAmount = 123e6;
        uint256 minimumMint = 123e6;
        uint256 deadline = block.timestamp + 1000;
        address spender = address(communityCodeDepositor);

        // owner is the depositor aka msg.sender to the depositor contract
        uint256 ownerSk = uint256(bytes32("owner_private_key"));
        address owner = vm.addr(ownerSk);

        uint256 incorrectSk = uint256(bytes32("incorrect_private_key"));
        address incorrectOwner = vm.addr(incorrectSk);

        _setERC20Balance(address(USDC), owner, depositAmount);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            IERC2612(address(USDC)),
            owner,
            incorrectSk, // sign with a wrong private key
            spender,
            depositAmount,
            deadline
        );

        // deposit without approval
        vm.startPrank(owner);
        vm.expectRevert("EIP2612: invalid signature");
        uint256 sharesMinted = communityCodeDepositor.depositWithPermit(
            ERC20(address(USDC)), depositAmount, minimumMint, owner, "test code", deadline, v, r, s
        );
        vm.stopPrank();
    }

    function _signPermit(
        IERC2612 token,
        address owner,
        uint256 ownerSk,
        address spender,
        uint256 depositAmount,
        uint256 deadline
    )
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash = keccak256(
            abi.encode(token.PERMIT_TYPEHASH(), owner, spender, depositAmount, token.nonces(owner), deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerSk, digest);
        return (v, r, s);
    }
}
