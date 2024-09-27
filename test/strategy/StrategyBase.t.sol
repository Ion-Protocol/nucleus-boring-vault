// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MainnetAddresses } from "test/resources/MainnetAddresses.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { LiveSetup } from "../LiveSetup.t.sol";

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

struct Leaf {
    address decoderAndSanitizer;
    address target;
    bool valueNonZero;
    bytes4 selector;
    bytes packedArgumentAddresses;
}

uint256 constant EXAMPLE_TREE_SIZE = 8;

abstract contract StrategyBase is LiveSetup {
    function setUp() public virtual override {
        super.setUp();
        setUpDecoderSanitizers();
    }

    address[] public decoderAndSanitizers;
    bytes32[][] tree;

    function setUpDecoderSanitizers() public virtual;

    function buildExampleTree(Leaf memory leaf) public {
        Leaf[] memory leafs = new Leaf[](EXAMPLE_TREE_SIZE);
        // users leaf is first one
        leafs[0] = leaf;
        // fill others with random data
        for (uint256 i = 1; i < EXAMPLE_TREE_SIZE; ++i) {
            leafs[i] = Leaf(
                address(bytes20(bytes32(i))), address(bytes20(bytes32((i * EXAMPLE_TREE_SIZE)))), false, 0x00000000, ""
            );
        }
        tree = _generateMerkleTree(leafs);
    }

    function _hashLeaf(Leaf memory leaf) internal returns (bytes32 leafHash) {
        leafHash = keccak256(
            abi.encodePacked(
                leaf.decoderAndSanitizer, leaf.target, leaf.valueNonZero, leaf.selector, leaf.packedArgumentAddresses
            )
        );
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

    function _getRoot() internal returns (bytes32) {
        return tree[tree.length - 1][0];
    }

    function _getProofsUsingTree(
        Leaf[] memory leafs,
        bytes32[][] memory tree
    )
        internal
        view
        returns (bytes32[][] memory proofs)
    {
        proofs = new bytes32[][](leafs.length);
        for (uint256 i; i < leafs.length; ++i) {
            // Generate manage proof.
            bytes memory rawDigest = abi.encodePacked(
                leafs[i].decoderAndSanitizer,
                leafs[i].target,
                leafs[i].valueNonZero,
                leafs[i].selector,
                leafs[i].packedArgumentAddresses
            );
            bytes32 leaf = keccak256(rawDigest);
            proofs[i] = _generateProof(leaf, tree);
        }
    }

    // 2D bc it recurses as it builds new layers up to the root.
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

    function _generateMerkleTree(Leaf[] memory leafs) internal view returns (bytes32[][] memory tree) {
        uint256 leafsLength = leafs.length;
        bytes32[][] memory leafHashes = new bytes32[][](1);
        leafHashes[0] = new bytes32[](leafsLength);
        for (uint256 i; i < leafsLength; ++i) {
            bytes memory rawDigest = abi.encodePacked(
                leafs[i].decoderAndSanitizer,
                leafs[i].target,
                leafs[i].valueNonZero,
                leafs[i].selector,
                leafs[i].packedArgumentAddresses
            );
            leafHashes[0][i] = keccak256(rawDigest);
        }
        tree = _buildTrees(leafHashes);
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
}
