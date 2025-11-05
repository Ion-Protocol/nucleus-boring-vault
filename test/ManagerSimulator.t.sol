// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { ManagerSimulator } from "src/base/Roles/ManagerSimulator.sol";
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

contract ManagerSimulatorTest is Test, MainnetAddresses {

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    ManagerSimulator public manager;
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
        manager = new ManagerSimulator(18);

        boringVault.setAuthority(rolesAuthority);

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

    function testNativeToken() external {
        ManagerSimulator.ManageCall[] memory manageCalls = new ManagerSimulator.ManageCall[](0);

        deal(address(boringVault), 1000e18);
        uint256[] memory expectedAmounts = new uint256[](1);
        expectedAmounts[0] = address(boringVault).balance;

        address[] memory tokensForVerification = new address[](1);
        tokensForVerification[0] = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        vm.expectRevert(
            abi.encodeWithSelector(
                ManagerSimulator.ResultingTokenBalancesPostSimulation.selector, tokensForVerification, expectedAmounts
            )
        );
        manager.tokenBalancesSimulation(boringVault, manageCalls, tokensForVerification);
    }

    function testTokenBalancesSimulationReturnEachStep() external {
        // Allow the manager to call the USDC approve function to a specific address,
        // and the USDT transfer function to a specific address.
        address usdcReceiver = vm.addr(0xDEAD2);

        ManagerSimulator.ManageCall[] memory manageCalls = new ManagerSimulator.ManageCall[](2);
        manageCalls[0] = ManagerSimulator.ManageCall(
            address(USDC), abi.encodeWithSelector(ERC20.transfer.selector, usdcReceiver, 700), 0
        );

        manageCalls[1] = ManagerSimulator.ManageCall(
            address(USDC), abi.encodeWithSelector(ERC20.transfer.selector, usdcReceiver, 77), 0
        );

        // expect simulated amounts expected in boring vault after each step
        uint256[][] memory expectedAmounts = new uint256[][](3);
        expectedAmounts[0] = new uint256[](2);
        expectedAmounts[1] = new uint256[](2);
        expectedAmounts[2] = new uint256[](2);
        // Only initialize the first token (USDC) as WETH will stay 0
        expectedAmounts[0][0] = 777;
        expectedAmounts[1][0] = 77;
        expectedAmounts[2][0] = 0;

        // set up decimals
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 6;
        decimals[1] = 18;

        address[] memory tokens = new address[](2);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH); // Include WETH but expect all the balances to be 0

        deal(address(USDC), address(boringVault), 777);

        assertEq(USDC.balanceOf(address(boringVault)), 777, "USDC should have a balance of 777");

        vm.expectRevert(
            abi.encodeWithSelector(
                ManagerSimulator.ResultingTokenBalancesEachStepPostSimulation.selector,
                tokens,
                decimals,
                expectedAmounts
            )
        );
        manager.tokenBalancesSimulationReturnEachStep(boringVault, manageCalls, tokens);
    }

    function testTokenBalNow() external {
        // Allow the manager to call the USDC approve function to a specific address,
        // and the USDT transfer function to a specific address.
        address usdcReceiver = vm.addr(0xDEAD2);

        ManagerSimulator.ManageCall[] memory manageCalls = new ManagerSimulator.ManageCall[](1);
        manageCalls[0] = ManagerSimulator.ManageCall(
            address(USDC), abi.encodeWithSelector(ERC20.transfer.selector, usdcReceiver, 777), 0
        );

        address[] memory tokensForVerification = new address[](1);
        tokensForVerification[0] = address(USDC);
        deal(address(USDC), address(boringVault), 777);

        uint256 gas = gasleft();
        console.log("before manage");
        assertEq(USDC.balanceOf(address(boringVault)), 777, "USDC should have a balance of 777");
        // the function should revert with the post simulation balance as 0
        vm.expectRevert(
            abi.encodeWithSelector(
                ManagerSimulator.ResultingTokenBalancesPostSimulation.selector, tokensForVerification, new uint256[](1)
            )
        );
        manager.tokenBalancesSimulation(boringVault, manageCalls, tokensForVerification);
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }

}
