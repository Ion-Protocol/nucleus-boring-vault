// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import {
    ManagerWithTokenBalanceVerification,
    ManagerSimulator
} from "src/base/Roles/ManagerWithTokenBalanceVerification.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import {
    EtherFiLiquidDecoderAndSanitizer,
    MorphoBlueDecoderAndSanitizer,
    UniswapV3DecoderAndSanitizer,
    BalancerV2DecoderAndSanitizer,
    PendleRouterDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/EtherFiLiquidDecoderAndSanitizer.sol";
import { EtherFiLiquidDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/EtherFiLiquidDecoderAndSanitizer.sol";
import { LidoLiquidDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/LidoLiquidDecoderAndSanitizer.sol";
import { BalancerVault } from "src/interfaces/BalancerVault.sol";
import { IUniswapV3Router } from "src/interfaces/IUniswapV3Router.sol";
import { DecoderCustomTypes } from "src/interfaces/DecoderCustomTypes.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";
import {
    PointFarmingDecoderAndSanitizer,
    EigenLayerLSTStakingDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/PointFarmingDecoderAndSanitizer.sol";

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

contract ManagerWithTokenBalanceVerificationTest is Test, MainnetAddresses {

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    ManagerWithTokenBalanceVerification public manager;
    BoringVault public boringVault;
    address public rawDataDecoderAndSanitizer;
    RolesAuthority public rolesAuthority;

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 2;
    uint8 public constant MANGER_INTERNAL_ROLE = 3;
    uint8 public constant ADMIN_ROLE = 4;
    uint8 public constant BORING_VAULT_ROLE = 5;
    uint8 public constant BALANCER_VAULT_ROLE = 6;

    address public weEthOracle = 0x3fa58b74e9a8eA8768eb33c8453e9C2Ed089A40a;
    address public weEthIrm = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        // uint256 blockNumber = 19369928;
        uint256 blockNumber = 19_826_676;

        _startFork(rpcKey, blockNumber);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 18);

        rawDataDecoderAndSanitizer =
            address(new EtherFiLiquidDecoderAndSanitizer(address(boringVault), uniswapV3NonFungiblePositionManager));

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        manager = new ManagerWithTokenBalanceVerification(18, address(this));

        manager.setAuthority(rolesAuthority);

        boringVault.setAuthority(rolesAuthority);
        manager.setAuthority(rolesAuthority);

        // Setup roles authority.
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(boringVault),
            bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)"))),
            true
        );
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(boringVault),
            bytes4(keccak256(abi.encodePacked("manage(address[],bytes[],uint256[])"))),
            true
        );

        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(manager),
            bytes4(
                keccak256(
                    abi.encodePacked(
                        "manageVaultWithTokenBalanceVerification((address,bytes,uint256)[],address[],int256[])"
                    )
                )
            ),
            true
        );

        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(manager),
            bytes4(keccak256(abi.encodePacked("manageVaultWithTokenBalanceVerification((address,bytes,uint256)[]"))),
            true
        );

        // Grant roles
        rolesAuthority.setUserRole(address(this), STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANGER_INTERNAL_ROLE, true);
        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(address(boringVault), BORING_VAULT_ROLE, true);
        rolesAuthority.setUserRole(vault, BALANCER_VAULT_ROLE, true);

        // Allow the boring vault to receive ETH.
        rolesAuthority.setPublicCapability(address(boringVault), bytes4(0), true);
    }

    function testManagerSimpleHappyPath() external {
        // Allow the manager to call the USDC approve function to a specific address,
        // and the USDT transfer function to a specific address.
        address usdcSpender = vm.addr(0xDEAD);
        address usdtTo = vm.addr(0xDEAD1);

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSelector(ERC20.approve.selector, usdcSpender, 777);
        values[0] = 0;

        targets[1] = address(USDT);
        data[1] = abi.encodeWithSelector(ERC20.approve.selector, usdtTo, 777);
        values[1] = 0;

        deal(address(USDT), address(boringVault), 777);

        uint256 gas = gasleft();
        manager.manageVaultWithNoVerification(boringVault, targets, data, values);
        console.log("Gas used", gas - gasleft());

        assertEq(USDC.allowance(address(boringVault), usdcSpender), 777, "USDC should have an allowance");
        assertEq(USDT.allowance(address(boringVault), usdtTo), 777, "USDT should have have an allowance");
    }

    function testOnlyOwnerCanCall(address caller) external {
        if (caller == address(this)) return;
        vm.startPrank(caller);

        address[] memory tokensForVerification = new address[](1);
        tokensForVerification[0] = address(USDC);
        int256[] memory allowableTokenDelta = new int256[](1);
        allowableTokenDelta[0] = 0;

        address usdcSpender = vm.addr(0xDEAD);
        address usdtTo = vm.addr(0xDEAD1);

        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSelector(ERC20.approve.selector, usdcSpender, 777);
        values[0] = 0;

        targets[1] = address(USDT);
        data[1] = abi.encodeWithSelector(ERC20.approve.selector, usdtTo, 777);
        values[1] = 0;

        deal(address(USDT), address(boringVault), 777);

        (bool success,) = address(manager)
            .call(
                abi.encodeWithSelector(
                    ManagerWithTokenBalanceVerification.manageVaultWithTokenBalanceVerification.selector,
                    boringVault,
                    targets,
                    data,
                    values,
                    tokensForVerification,
                    allowableTokenDelta
                )
            );
        assertFalse(
            success, "non-owner should never be able to successfully call manageVaultWithTokenBalanceVerification"
        );
        (success,) = address(manager)
            .call(
                abi.encodeWithSelector(
                    ManagerWithTokenBalanceVerification.manageVaultWithNoVerification.selector,
                    boringVault,
                    targets,
                    data,
                    values
                )
            );
        assertFalse(success, "non-owner should never be able to successfully call manageVaultWithNoVerification");

        vm.stopPrank();

        manager.transferOwnership(caller);

        vm.startPrank(caller);

        data[1] = abi.encodeWithSelector(ERC20.approve.selector, usdtTo, 0);
        (success,) = address(manager)
            .call(
                abi.encodeWithSelector(
                    ManagerWithTokenBalanceVerification.manageVaultWithTokenBalanceVerification.selector,
                    boringVault,
                    targets,
                    data,
                    values,
                    tokensForVerification,
                    allowableTokenDelta
                )
            );
        assertTrue(success, "owner should always be able to successfully call manageVaultWithTokenBalanceVerification");

        data[1] = abi.encodeWithSelector(ERC20.approve.selector, usdtTo, 777);
        (success,) = address(manager)
            .call(
                abi.encodeWithSelector(
                    ManagerWithTokenBalanceVerification.manageVaultWithNoVerification.selector,
                    boringVault,
                    targets,
                    data,
                    values
                )
            );
        assertTrue(success, "owner should always be able to successfully call manageVaultWithNoVerification");

        assertEq(USDC.allowance(address(boringVault), usdcSpender), 777, "USDC should have an allowance");
        assertEq(USDT.allowance(address(boringVault), usdtTo), 777, "USDT should have have an allowance");
    }

    function testManagerWithTokenBalanceVerificationHappyPath() external {
        // Allow the manager to call the USDC approve function to a specific address,
        // and the USDT transfer function to a specific address.
        address usdcReceiver = vm.addr(0xDEAD2);

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(USDC);
        data[0] = abi.encodeWithSelector(ERC20.transfer.selector, usdcReceiver, 777);
        values[0] = 0;

        address[] memory tokensForVerification = new address[](1);
        tokensForVerification[0] = address(USDC);
        int256[] memory allowableTokenDelta = new int256[](1);
        allowableTokenDelta[0] = -777;
        deal(address(USDC), address(boringVault), 777);

        uint256 gas = gasleft();
        console.log("before manage");
        manager.manageVaultWithTokenBalanceVerification(
            boringVault, targets, data, values, tokensForVerification, allowableTokenDelta
        );
        console.log("Gas used", gas - gasleft());

        assertEq(USDC.balanceOf(address(boringVault)), 0, "USDC should have all been transferred to the receiver");
        assertEq(USDC.balanceOf(usdcReceiver), 777, "USDC should have all been received by the receiver");

        deal(address(USDC), address(boringVault), 777);
        allowableTokenDelta[0] = -776;
        vm.expectRevert(
            abi.encodeWithSelector(
                ManagerWithTokenBalanceVerification.ManagerWithTokenBalanceVerification__TokenDeltaViolation.selector,
                address(USDC),
                777,
                0,
                -777,
                -776
            )
        );
        manager.manageVaultWithTokenBalanceVerification(
            boringVault, targets, data, values, tokensForVerification, allowableTokenDelta
        );
    }

    function testReverts() external {
        address[] memory tokensForVerification;
        int256[] memory allowableTokenDelta = new int256[](1);

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ManagerWithTokenBalanceVerification.ManagerWithTokenBalanceVerification__InvalidArrayLength.selector
            )
        );
        manager.manageVaultWithTokenBalanceVerification(
            boringVault, targets, data, values, tokensForVerification, allowableTokenDelta
        );

        tokensForVerification = new address[](1);
        tokensForVerification[0] = vm.addr(0xDEAD);

        // this one here
        vm.expectRevert(
            abi.encodeWithSelector(ManagerSimulator.ManagerSimulator__TokenHasNoCode.selector, tokensForVerification[0])
        );

        manager.manageVaultWithTokenBalanceVerification(
            boringVault, targets, data, values, tokensForVerification, allowableTokenDelta
        );

        tokensForVerification[0] = address(USDC);
        targets[0] = address(USDC);
        data[0] = abi.encodeWithSignature("notReal()");
        values[0] = 0;

        bytes4 FAILED_CALL = 0xd6bda275;

        // Expect the failed call directly and not within a handled error unlike the simulation function
        vm.expectRevert(abi.encodePacked(FAILED_CALL));
        manager.manageVaultWithTokenBalanceVerification(
            boringVault, targets, data, values, tokensForVerification, allowableTokenDelta
        );
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }

}
