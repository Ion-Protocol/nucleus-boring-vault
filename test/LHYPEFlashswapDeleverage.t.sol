// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { LHYPEFlashswapDeleverage, IGetRate } from "src/helper/LHYPEFlashswapDeleverage.sol";
import { LHYPEDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/LHYPEDecoderAndSanitizer.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract LHYPEFlashswapDeleverageTest is Test {

    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    ERC20 WHYPE_DEBT_HLEND = ERC20(0x747d0d4Ba0a2083651513cd008deb95075683e82);
    ERC20 wstHYPE_COLLATERAL_HLEND = ERC20(0x0Ab8AAE3335Ed4B373A33D9023b6A6585b149D33);

    ERC20 WHYPE_DEBT_HFI = ERC20(0x37E44F3070b5455f1f5d7aaAd9Fc8590229CC5Cb);
    ERC20 wstHYPE_COLLATERAL_HFI = ERC20(0xC8b6E0acf159E058E22c564C0C513ec21f8a1Bf5);

    // Mock addresses - Replace with actual addresses in production
    address public constant wstHYPE = 0x94e8396e0869c9F2200760aF0621aFd240E1CF38;
    address public constant stHYPE = 0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1;
    address public constant WHYPE = 0x5555555555555555555555555555555555555555;

    IPool public hypurrfiPool_hfi = IPool(0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b);
    IPool public hyperlendPool_hlend = IPool(0x00A89d7a5A02160f20150EbEA7a2b5E4879A1A8b);
    IUniswapV3Pool public hyperswapPool = IUniswapV3Pool(0x8D64d8273a3D50E44Cc0e6F43d927f78754EdefB);

    BoringVault public boringVault;
    ManagerWithMerkleVerification public manager;
    LHYPEDecoderAndSanitizer public lhypeDecoderAndSanitizer;
    LHYPEFlashswapDeleverage public lhypeDeleverage_hfi;
    LHYPEFlashswapDeleverage public lhypeDeleverage_hlend;
    RolesAuthority public rolesAuthority;

    IPool public pool_hfi = IPool(0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b);

    uint256 wstHypeRate;

    function setUp() external {
        // Setup forked environment. On Hyperliquid
        string memory rpcKey = "HL_RPC_URL";
        uint256 blockNumber = 9_902_287;
        _startFork(rpcKey, blockNumber);

        wstHypeRate = IGetRate(stHYPE).balancePerShare();

        manager = ManagerWithMerkleVerification(0xe661393C409f7CAec8564bc49ED92C22A63e81d0);
        boringVault = manager.vault();
        rolesAuthority = RolesAuthority(0xDc4605f2332Ba81CdB5A6f84cB1a6356198D11f6);
        lhypeDecoderAndSanitizer =
            new LHYPEDecoderAndSanitizer(address(boringVault), 0x6eDA206207c09e5428F281761DdC0D300851fBC8);

        lhypeDeleverage_hfi = new LHYPEFlashswapDeleverage(address(hypurrfiPool_hfi), address(hyperswapPool), manager);
        lhypeDeleverage_hlend =
            new LHYPEFlashswapDeleverage(address(hyperlendPool_hlend), address(hyperswapPool), manager);
        vm.startPrank(rolesAuthority.owner());
        rolesAuthority.setUserRole(address(lhypeDeleverage_hfi), 1, true);
        rolesAuthority.setUserRole(address(lhypeDeleverage_hlend), 1, true);
        vm.stopPrank();
    }

    function testDeleverageWithMerkleProof() external {
        uint256 hypeToDeleverage = 100e18;
        uint256 maxStHypePaid = 110e18;
        uint256 minimumEndingHealthFactor = 1_050_000_000_000_000_000; // 1.05

        bytes32[] memory proof = _setRootAndGetProof(address(hypurrfiPool_hfi), address(lhypeDeleverage_hfi));
        // Call deleverage with merkle proof
        vm.prank(address(boringVault));
        uint256 stHypePaid = lhypeDeleverage_hfi.deleverage(
            hypeToDeleverage, maxStHypePaid, minimumEndingHealthFactor, proof, address(lhypeDecoderAndSanitizer)
        );

        // Basic assertions
        assertTrue(stHypePaid <= maxStHypePaid, "Should not exceed max stHYPE paid");
    }

    function test_deleverage_fails_when_slippage_too_high_hfi() public {
        uint256 hypeToDeleverage = 10_000e18;
        uint256 maxStHypeWithdrawn = 10_000e18;
        uint256 realStHypeWithdrawn = 10_052_578_589_887_917_685_505;
        uint256 minimumEndingHealthFactor = 1_170_000_000_000_000_000;
        bytes32[] memory proof = _setRootAndGetProof(address(hypurrfiPool_hfi), address(lhypeDeleverage_hfi));

        vm.prank(address(boringVault));
        vm.expectRevert(
            abi.encodeWithSelector(
                LHYPEFlashswapDeleverage.LHYPEFlashswapDeleverage__SlippageTooHigh.selector,
                realStHypeWithdrawn,
                maxStHypeWithdrawn
            )
        );
        lhypeDeleverage_hfi.deleverage(
            hypeToDeleverage, maxStHypeWithdrawn, minimumEndingHealthFactor, proof, address(lhypeDecoderAndSanitizer)
        );
    }

    /// @dev test that the deleverage will succeed no matter the values put in assuming generous enough bounds
    function test_can_deleverage_hfi(uint256 hypeToDeleverage) public {
        hypeToDeleverage = bound(hypeToDeleverage, 1, 40_000e18);
        uint256 maxStHypeWithdrawn = hypeToDeleverage * 10;
        bytes32[] memory proof = _setRootAndGetProof(address(hypurrfiPool_hfi), address(lhypeDeleverage_hfi));

        vm.prank(address(boringVault));
        lhypeDeleverage_hfi.deleverage(
            hypeToDeleverage, maxStHypeWithdrawn, 1_050_000_000_000_000_000, proof, address(lhypeDecoderAndSanitizer)
        );
    }

    /// @dev test that the deleverage will succeed no matter the values put in assuming generous enough bounds
    function test_can_deleverage_hlend(uint256 hypeToDeleverage) public {
        hypeToDeleverage = bound(hypeToDeleverage, 1, 40_000e18);
        uint256 maxStHypeWithdrawn = hypeToDeleverage * 10;
        bytes32[] memory proof = _setRootAndGetProof(address(hyperlendPool_hlend), address(lhypeDeleverage_hlend));

        vm.prank(address(boringVault));
        lhypeDeleverage_hlend.deleverage(
            hypeToDeleverage, maxStHypeWithdrawn, 1_050_000_000_000_000_000, proof, address(lhypeDecoderAndSanitizer)
        );
    }

    function test_deleverage_hfi() public {
        // TODO: More accurate numbers here
        uint256 hypeToDeleverage = 10_000e18;
        uint256 maxStHypeWithdrawn = 10_053e18;

        (
            uint256 totalCollateralBaseBefore,
            uint256 totalDebtBaseBefore,,
            uint256 liquidationThresholdBefore,,
            uint256 healthFactorBefore
        ) = pool_hfi.getUserAccountData(address(boringVault));

        uint256 debtBefore = WHYPE_DEBT_HFI.balanceOf(address(boringVault));
        uint256 collateralBefore = wstHYPE_COLLATERAL_HFI.balanceOf(address(boringVault));

        bytes32[] memory proof = _setRootAndGetProof(address(hypurrfiPool_hfi), address(lhypeDeleverage_hfi));

        vm.prank(address(boringVault));
        uint256 amountWstHypePaid = lhypeDeleverage_hfi.deleverage(
            hypeToDeleverage, maxStHypeWithdrawn, healthFactorBefore, proof, address(lhypeDecoderAndSanitizer)
        );
        console.log("liquidationThresholdBefore", liquidationThresholdBefore);

        uint256 expectedHealthFactor = ((collateralBefore - amountWstHypePaid) * wstHypeRate / 1e18)
            * liquidationThresholdBefore * 1e18 / (debtBefore - hypeToDeleverage) / 1e4; // divide 1e4 because
        // liquidation
        // threshold has 4 decimals

        (uint256 totalCollateralBaseAfter, uint256 totalDebtBaseAfter,,,, uint256 healthFactorAfter) =
            pool_hfi.getUserAccountData(address(boringVault));

        console.log("collateralBefore", collateralBefore);
        // console.log("collateralAfter", collateralAfter);
        console.log("debtBefore", debtBefore);
        // console.log("debtAfter", debtAfter);
        console.log("totalCollateralBaseBefore", totalCollateralBaseBefore);
        console.log("totalCollateralBaseAfter", totalCollateralBaseAfter);
        console.log("totalDebtBaseBefore", totalDebtBaseBefore);
        console.log("totalDebtBaseAfter", totalDebtBaseAfter);
        console.log("healthFactor before", healthFactorBefore);
        console.log("healthFactor after", healthFactorAfter);

        assertApproxEqAbs(healthFactorAfter, expectedHealthFactor, 1e14);
        assertGt(healthFactorAfter, healthFactorBefore, "Health factor should improve");
    }

    function test_deleverage_fails_when_health_factor_below_minimum_hlend() public {
        uint256 hypeToDeleverage = 10_000e18;
        uint256 maxStHypeWithdrawn = 10_053e18;
        uint256 minimumEndingHealthFactor = 1_190_000_000_000_000_000;
        uint256 realEndingHealthFactor = 1_170_216_497_003_944_136;

        bytes32[] memory proof = _setRootAndGetProof(address(hyperlendPool_hlend), address(lhypeDeleverage_hlend));

        vm.prank(address(boringVault));
        vm.expectRevert(
            abi.encodeWithSelector(
                LHYPEFlashswapDeleverage.LHYPEFlashswapDeleverage__HealthFactorBelowMinimum.selector,
                realEndingHealthFactor,
                minimumEndingHealthFactor
            )
        );
        lhypeDeleverage_hlend.deleverage(
            hypeToDeleverage, maxStHypeWithdrawn, minimumEndingHealthFactor, proof, address(lhypeDecoderAndSanitizer)
        );
    }

    function test_deleverage_fails_when_slippage_too_high_hlend() public {
        uint256 hypeToDeleverage = 10_000e18;
        uint256 maxStHypeWithdrawn = 10_040e18;
        uint256 realStHypeWithdrawn = 10_052_578_589_887_917_685_505;
        uint256 minimumEndingHealthFactor = 1_170_000_000_000_000_000;
        bytes32[] memory proof = _setRootAndGetProof(address(hyperlendPool_hlend), address(lhypeDeleverage_hlend));

        vm.prank(address(boringVault));
        vm.expectRevert(
            abi.encodeWithSelector(
                LHYPEFlashswapDeleverage.LHYPEFlashswapDeleverage__SlippageTooHigh.selector,
                realStHypeWithdrawn,
                maxStHypeWithdrawn
            )
        );
        lhypeDeleverage_hlend.deleverage(
            hypeToDeleverage, maxStHypeWithdrawn, minimumEndingHealthFactor, proof, address(lhypeDecoderAndSanitizer)
        );
    }

    function test_deleverage_hlend() public {
        // TODO: More accurate numbers here
        uint256 hypeToDeleverage = 10_000e18;
        uint256 maxStHypeWithdrawn = 10_053e18;

        (
            uint256 totalCollateralBaseBefore,
            uint256 totalDebtBaseBefore,,
            uint256 liquidationThresholdBefore,,
            uint256 healthFactorBefore
        ) = hyperlendPool_hlend.getUserAccountData(address(boringVault));

        uint256 debtBefore = WHYPE_DEBT_HLEND.balanceOf(address(boringVault));
        uint256 collateralBefore = wstHYPE_COLLATERAL_HLEND.balanceOf(address(boringVault));

        bytes32[] memory proof = _setRootAndGetProof(address(hyperlendPool_hlend), address(lhypeDeleverage_hlend));

        vm.prank(address(boringVault));
        uint256 amountWstHypePaid = lhypeDeleverage_hlend.deleverage(
            hypeToDeleverage, maxStHypeWithdrawn, healthFactorBefore, proof, address(lhypeDecoderAndSanitizer)
        );
        console.log("liquidationThresholdBefore", liquidationThresholdBefore);

        uint256 expectedHealthFactor = ((collateralBefore - amountWstHypePaid) * wstHypeRate / 1e18)
            * liquidationThresholdBefore * 1e18 / (debtBefore - hypeToDeleverage) / 1e4; // divide 1e4 because
        // liquidation
        // threshold has 4 decimals

        (uint256 totalCollateralBaseAfter, uint256 totalDebtBaseAfter,,,, uint256 healthFactorAfter) =
            hyperlendPool_hlend.getUserAccountData(address(boringVault));

        console.log("collateralBefore", collateralBefore);
        // console.log("collateralAfter", collateralAfter);
        console.log("debtBefore", debtBefore);
        // console.log("debtAfter", debtAfter);
        console.log("totalCollateralBaseBefore", totalCollateralBaseBefore);
        console.log("totalCollateralBaseAfter", totalCollateralBaseAfter);
        console.log("totalDebtBaseBefore", totalDebtBaseBefore);
        console.log("totalDebtBaseAfter", totalDebtBaseAfter);
        console.log("healthFactor before", healthFactorBefore);
        console.log("healthFactor after", healthFactorAfter);
        console.log("expectedHealthFactor", expectedHealthFactor);

        assertApproxEqAbs(healthFactorAfter, expectedHealthFactor, 1e14);
        assertGt(healthFactorAfter, healthFactorBefore, "Health factor should improve");
    }

    function _setRootAndGetProof(address pool, address deleverage) internal returns (bytes32[] memory proof) {
        address[] memory argumentAddresses = new address[](2);
        // Setup merkle tree with withdraw function for wstHYPE
        ManageLeaf[] memory leafs = new ManageLeaf[](1);
        leafs[0] = ManageLeaf({
            target: pool,
            canSendValue: false,
            signature: "withdraw(address,uint256,address)",
            argumentAddresses: argumentAddresses
        });
        argumentAddresses[0] = wstHYPE;
        argumentAddresses[1] = deleverage;

        // Generate merkle tree
        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        // Set the manage root
        vm.prank(boringVault.owner());
        manager.setManageRoot(deleverage, manageTree[manageTree.length - 1][0]);

        // Generate proofs
        bytes32[][] memory manageProofs = _getProofsUsingTree(leafs, manageTree);
        return manageProofs[0];
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }

    struct ManageLeaf {
        address target;
        bool canSendValue;
        string signature;
        address[] argumentAddresses;
    }

    function _generateMerkleTree(ManageLeaf[] memory manageLeafs) internal view returns (bytes32[][] memory tree) {
        uint256 leafsLength = manageLeafs.length;
        bytes32[][] memory leafs = new bytes32[][](1);
        leafs[0] = new bytes32[](leafsLength);
        for (uint256 i; i < leafsLength; ++i) {
            bytes4 selector = bytes4(keccak256(abi.encodePacked(manageLeafs[i].signature)));
            bytes memory rawDigest = abi.encodePacked(
                lhypeDecoderAndSanitizer, manageLeafs[i].target, manageLeafs[i].canSendValue, selector
            );
            uint256 argumentAddressesLength = manageLeafs[i].argumentAddresses.length;
            for (uint256 j; j < argumentAddressesLength; ++j) {
                rawDigest = abi.encodePacked(rawDigest, manageLeafs[i].argumentAddresses[j]);
            }
            leafs[0][i] = keccak256(rawDigest);
        }
        tree = _buildTrees(leafs);
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
            bytes4 selector = bytes4(keccak256(abi.encodePacked(manageLeafs[i].signature)));
            bytes memory rawDigest = abi.encodePacked(
                address(lhypeDecoderAndSanitizer), manageLeafs[i].target, manageLeafs[i].canSendValue, selector
            );
            uint256 argumentAddressesLength = manageLeafs[i].argumentAddresses.length;
            for (uint256 j; j < argumentAddressesLength; ++j) {
                rawDigest = abi.encodePacked(rawDigest, manageLeafs[i].argumentAddresses[j]);
            }
            bytes32 leaf = keccak256(rawDigest);
            proofs[i] = _generateProof(leaf, tree);
        }
    }

    function _generateProof(bytes32 leaf, bytes32[][] memory tree) internal pure returns (bytes32[] memory proof) {
        uint256 tree_length = tree.length;
        proof = new bytes32[](tree_length - 1);
        for (uint256 i; i < tree_length - 1; ++i) {
            for (uint256 j; j < tree[i].length; ++j) {
                if (leaf == tree[i][j]) {
                    // Check bounds before accessing sibling
                    if (j % 2 == 0) {
                        // Even index: get right sibling (j + 1)
                        if (j + 1 < tree[i].length) {
                            proof[i] = tree[i][j + 1];
                        } else {
                            // No right sibling (odd number of elements), duplicate current
                            proof[i] = tree[i][j];
                        }
                    } else {
                        // Odd index: get left sibling (j - 1)
                        proof[i] = tree[i][j - 1];
                    }
                    leaf = _hashPair(leaf, proof[i]);
                    break;
                }
            }
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
            if (i + 1 < layer_length) {
                // Normal case: hash two elements
                merkleTreeOut[merkleTreeIn_length][count] =
                    _hashPair(merkleTreeIn[merkleTreeIn_length - 1][i], merkleTreeIn[merkleTreeIn_length - 1][i + 1]);
            } else {
                // Odd case: hash the element with itself
                merkleTreeOut[merkleTreeIn_length][count] =
                    _hashPair(merkleTreeIn[merkleTreeIn_length - 1][i], merkleTreeIn[merkleTreeIn_length - 1][i]);
            }
            count++;
        }

        if (next_layer_length > 1) {
            // We need to process the next layer of leaves.
            merkleTreeOut = _buildTrees(merkleTreeOut);
        }
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
