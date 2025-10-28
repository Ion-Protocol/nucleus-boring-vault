// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
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
import { VelodromeBuyback } from "src/helper/VelodromeBuyback.sol";

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { LHYPEDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/LHYPEDecoderAndSanitizer.sol";
import { IVelodromeV1Router } from "src/interfaces/IVelodromeV1Router.sol";

contract ManagerWithMerkleVerificationTest is Test, MainnetAddresses {

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    ManagerWithMerkleVerification public manager;
    BoringVault public boringVault;
    address public rawDataDecoderAndSanitizer;
    RolesAuthority public rolesAuthority;
    VelodromeBuyback public buyBackBot;

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 2;
    uint8 public constant MANGER_INTERNAL_ROLE = 3;
    uint8 public constant ADMIN_ROLE = 4;
    uint8 public constant BORING_VAULT_ROLE = 5;
    uint8 public constant BALANCER_VAULT_ROLE = 6;

    ERC20 public WHYPE = ERC20(0x5555555555555555555555555555555555555555);
    AccountantWithRateProviders public accountant;
    TellerWithMultiAssetSupport public teller;
    address public constant MULTISIG = 0x413f2e80070a069eB1051772Fdc4f0af8e8303d7;
    IVelodromeV1Router public router = IVelodromeV1Router(0xD6EeFfbDAF6503Ad6539CF8f337D79BEbbd40802);

    struct ManageLeaf {
        address target;
        bool canSendValue;
        string signature;
        address[] argumentAddresses;
    }

    function setUp() external {
        // Setup forked environment.
        string memory rpcKey = "HL_RPC_URL";
        _startFork(rpcKey, 1_956_681);
        vm.startPrank(MULTISIG);
        boringVault = BoringVault(payable(0x5748ae796AE46A4F1348a1693de4b50560485562));

        manager = ManagerWithMerkleVerification(0xe661393C409f7CAec8564bc49ED92C22A63e81d0);

        accountant = AccountantWithRateProviders(0xcE621a3CA6F72706678cFF0572ae8d15e5F001c3);
        teller = TellerWithMultiAssetSupport(0xFd83C1ca0c04e096d129275126fade1dC45BF4F0);

        rawDataDecoderAndSanitizer =
            address(new LHYPEDecoderAndSanitizer(address(boringVault), uniswapV3NonFungiblePositionManager));

        rolesAuthority = RolesAuthority(0xDc4605f2332Ba81CdB5A6f84cB1a6356198D11f6);

        buyBackBot = new VelodromeBuyback(address(router), accountant, address(boringVault));
        vm.stopPrank();
    }

    function testBuyBackBotManage(uint256 amount) external {
        // based on liquidity, larger bounds will either fail or get underflow errors
        amount = bound(amount, 0.0000000001e18, 10_000e18);
        vm.startPrank(MULTISIG);
        ManageLeaf[] memory leafs = new ManageLeaf[](2);
        leafs[0] = ManageLeaf(address(WHYPE), false, "approve(address,uint256)", new address[](1));
        leafs[0].argumentAddresses[0] = address(buyBackBot);
        leafs[1] = ManageLeaf(address(buyBackBot), false, "buyAndSwapEnforcingRate(address,uint256)", new address[](1));
        leafs[1].argumentAddresses[0] = address(WHYPE);

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        manager.setManageRoot(MULTISIG, manageTree[1][0]);

        address[] memory targets = new address[](2);
        targets[0] = address(WHYPE);
        targets[1] = address(buyBackBot);

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSelector(ERC20.approve.selector, address(buyBackBot), amount);
        targetData[1] =
            abi.encodeWithSelector(VelodromeBuyback.buyAndSwapEnforcingRate.selector, address(WHYPE), amount);

        (bytes32[][] memory manageProofs) = _getProofsUsingTree(leafs, manageTree);

        uint256[] memory values = new uint256[](2);

        deal(address(WHYPE), address(boringVault), amount);

        // send a bunch to the pool to make sure the buyback bot will be able to be ran
        deal(address(boringVault), MULTISIG, 100_000e18);
        boringVault.approve(address(router), 100_000e18);
        router.swapExactTokensForTokensSimple(
            100_000e18, 0, address(boringVault), address(WHYPE), true, address(0xdead), block.timestamp
        );

        address[] memory decodersAndSanitizers = new address[](2);
        decodersAndSanitizers[0] = rawDataDecoderAndSanitizer;
        decodersAndSanitizers[1] = rawDataDecoderAndSanitizer;

        uint256 balBefore = boringVault.balanceOf(address(boringVault));
        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);

        assertApproxEqRel(
            boringVault.balanceOf(address(boringVault)) - balBefore,
            amount * 1e18 / teller.accountant().getRateInQuote(WHYPE),
            0.2 * 1e18,
            "expected LHYPE balance of amount"
        );
        assertGe(
            boringVault.balanceOf(address(boringVault)) - balBefore,
            amount * 1e18 / teller.accountant().getRateInQuote(WHYPE),
            "must return more than rate"
        );
        vm.stopPrank();
    }

    function _generateProof(bytes32 leaf, bytes32[][] memory tree) internal pure returns (bytes32[] memory proof) {
        // The length of each proof is the height of the tree - 1.
        uint256 tree_length = tree.length;
        proof = new bytes32[](tree_length - 1);

        // Build the proof
        for (uint256 i; i < tree_length - 1; ++i) {
            // For each layer we need to find the leaf.
            for (uint256 j; j < tree[i].length; ++j) {
                if (leaf == tree[i][j]) {
                    // We have found the leaf, so now figure out if the proof needs the next leaf or the previous one.
                    proof[i] = j % 2 == 0 ? tree[i][j + 1] : tree[i][j - 1];
                    leaf = _hashPair(leaf, proof[i]);
                    break;
                }
            }
        }
    }

    function _getProofsUsingTree(
        ManageLeaf[] memory manageLeafs,
        bytes32[][] memory tree
    )
        internal
        view
        returns (bytes32[][] memory proofs)
    {
        proofs = new bytes32[][](manageLeafs.length);
        for (uint256 i; i < manageLeafs.length; ++i) {
            // Generate manage proof.
            bytes4 selector = bytes4(keccak256(abi.encodePacked(manageLeafs[i].signature)));
            bytes memory rawDigest = abi.encodePacked(
                rawDataDecoderAndSanitizer, manageLeafs[i].target, manageLeafs[i].canSendValue, selector
            );
            uint256 argumentAddressesLength = manageLeafs[i].argumentAddresses.length;
            for (uint256 j; j < argumentAddressesLength; ++j) {
                rawDigest = abi.encodePacked(rawDigest, manageLeafs[i].argumentAddresses[j]);
            }
            bytes32 leaf = keccak256(rawDigest);
            proofs[i] = _generateProof(leaf, tree);
        }
    }

    function _generateMerkleTree(ManageLeaf[] memory manageLeafs) internal view returns (bytes32[][] memory tree) {
        uint256 leafsLength = manageLeafs.length;
        bytes32[][] memory leafs = new bytes32[][](1);
        leafs[0] = new bytes32[](leafsLength);
        for (uint256 i; i < leafsLength; ++i) {
            bytes4 selector = bytes4(keccak256(abi.encodePacked(manageLeafs[i].signature)));
            bytes memory rawDigest = abi.encodePacked(
                rawDataDecoderAndSanitizer, manageLeafs[i].target, manageLeafs[i].canSendValue, selector
            );
            uint256 argumentAddressesLength = manageLeafs[i].argumentAddresses.length;
            for (uint256 j; j < argumentAddressesLength; ++j) {
                rawDigest = abi.encodePacked(rawDigest, manageLeafs[i].argumentAddresses[j]);
            }
            leafs[0][i] = keccak256(rawDigest);
        }
        tree = _buildTrees(leafs);
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
    }

    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function _buildTrees(bytes32[][] memory merkleTreeIn) internal pure returns (bytes32[][] memory merkleTreeOut) {
        // We are adding another row to the merkle tree, so make merkleTreeOut be 1 longer.
        uint256 merkleTreeIn_length = merkleTreeIn.length;
        merkleTreeOut = new bytes32[][](merkleTreeIn_length + 1);
        uint256 layer_length;
        // Iterate through merkleTreeIn to copy over data.
        for (uint256 i; i < merkleTreeIn_length; ++i) {
            layer_length = merkleTreeIn[i].length; // number of leafs
            merkleTreeOut[i] = new bytes32[](layer_length);
            for (uint256 j; j < layer_length; ++j) {
                merkleTreeOut[i][j] = merkleTreeIn[i][j];
            }
        }

        uint256 next_layer_length;
        if (layer_length % 2 != 0) {
            next_layer_length = (layer_length + 1) / 2;
        } else {
            next_layer_length = layer_length / 2;
        }
        merkleTreeOut[merkleTreeIn_length] = new bytes32[](next_layer_length);
        uint256 count;
        for (uint256 i; i < layer_length; i += 2) {
            merkleTreeOut[merkleTreeIn_length][count] =
                _hashPair(merkleTreeIn[merkleTreeIn_length - 1][i], merkleTreeIn[merkleTreeIn_length - 1][i + 1]);
            count++;
        }

        if (next_layer_length > 1) {
            // We need to process the next layer of leaves.
            merkleTreeOut = _buildTrees(merkleTreeOut);
        }
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }

}
