// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { console2 } from "forge-std/console2.sol";
import { stdJson } from "@forge-std/StdJson.sol";
import { EtherFiLiquidDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/EtherFiLiquidDecoderAndSanitizer.sol";

using stdJson for string;

/**
 * @notice made to test V2 Migrations as they are done.
 * IN: out.json from the migration script which contains deprecated addresses and new deployment addresses
 * TEST ASSERTS:
 *   1. All old addresses are paused
 *   2. The Boring Vault's roles authority is updated to the new one.
 *   3. The new roles authority didn't grant any roles to old contracts mistakenly
 *   4. The typical live test passes on the new vaults
 *   5. The multisig for this chain is the owner of all contracts and the authority
 */
contract LiveTest is Test {
    string constant DEFAULT_RPC_URL = "L1_RPC_URL";
    address multisig;

    // State variables for addresses from out.json
    BoringVault boringVault;
    ManagerWithMerkleVerification v1Manager;
    TellerWithMultiAssetSupport v1Teller;
    AccountantWithRateProviders v1Accountant;
    RolesAuthority v1RolesAuthority;
    ManagerWithMerkleVerification v2Manager;
    TellerWithMultiAssetSupport v2Teller;
    AccountantWithRateProviders v2Accountant;
    RolesAuthority v2RolesAuthority;

    // Add token references
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 constant USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address public rawDataDecoderAndSanitizer;

    struct ManageLeaf {
        address target;
        bool canSendValue;
        string signature;
        address[] argumentAddresses;
    }

    function setUp() external {
        _startFork(DEFAULT_RPC_URL);

        // Read and parse the out.json file
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/v2Migration/out.json");
        string memory json = vm.readFile(path);

        string memory chainPath = string.concat(root, "/deployment-config/chains/", vm.toString(block.chainid), ".json");
        string memory chainJson = vm.readFile(chainPath);

        multisig = chainJson.readAddress(".multisig"); // Parse addresses from JSON

        boringVault = BoringVault(payable(json.readAddress(".boringVault")));
        v1Manager = ManagerWithMerkleVerification(json.readAddress(".v1Manager"));
        v1Teller = TellerWithMultiAssetSupport(json.readAddress(".v1Teller"));
        v1Accountant = AccountantWithRateProviders(json.readAddress(".v1Accountant"));
        v1RolesAuthority = RolesAuthority(json.readAddress(".v1RolesAuthority"));
        v2Manager = ManagerWithMerkleVerification(json.readAddress(".v2Manager"));
        v2Teller = TellerWithMultiAssetSupport(json.readAddress(".v2Teller"));
        v2Accountant = AccountantWithRateProviders(json.readAddress(".v2Accountant"));
        v2RolesAuthority = RolesAuthority(json.readAddress(".v2RolesAuthority"));

        console.log("Loaded addresses from out.json:");
        console.log("boringVault:", address(boringVault));
        console.log("v1Manager:", address(v1Manager));
        console.log("v1Teller:", address(v1Teller));
        console.log("v1Accountant:", address(v1Accountant));
        console.log("v1RolesAuthority:", address(v1RolesAuthority));
        console.log("v2Manager:", address(v2Manager));
        console.log("v2Teller:", address(v2Teller));
        console.log("v2Accountant:", address(v2Accountant));
        console.log("v2RolesAuthority:", address(v2RolesAuthority));

        // Deploy and setup rawDataDecoderAndSanitizer
        rawDataDecoderAndSanitizer =
            address(new EtherFiLiquidDecoderAndSanitizer(address(boringVault), address(boringVault)));
    }

    function testV1Paused() external {
        assertTrue(v1Manager.isPaused(), "v1 manager is not paused");
        assertTrue(v1Teller.isPaused(), "v1 teller is not paused");
        (,,,,,,,, bool _isPaused,,,) = v1Accountant.accountantState();
        assertTrue(_isPaused, "v1 accountant is not paused");
    }

    function testBoringVaultIsUsingV2Authority() external {
        assertEq(
            address(boringVault.authority()),
            address(v2RolesAuthority),
            "Boring Vault should have authority updated to new v2 authority"
        );
        assertTrue(
            address(v1RolesAuthority) != address(v2RolesAuthority), "Roles Authorities V1 and V2 must be different"
        );
    }

    function testOwnerOfAllV2ContractsIsMultisig() external {
        assertEq(v2Manager.owner(), multisig, string.concat("v2 manager owner should be: ", vm.toString(multisig)));
        assertEq(v2Teller.owner(), multisig, string.concat("v2 teller owner should be: ", vm.toString(multisig)));
        assertEq(
            v2Accountant.owner(), multisig, string.concat("v2 accountant owner should be: ", vm.toString(multisig))
        );
        assertEq(
            v2RolesAuthority.owner(),
            multisig,
            string.concat("v2 roles authority owner should be: ", vm.toString(multisig))
        );
    }

    function testAuthorityV2HasNotGrantedAnyRolesOrPublicCapabilitiesToV1Contracts() external {
        assertEq(
            v2RolesAuthority.getUserRoles(address(v1Manager)),
            bytes32(0),
            "v1 Manager should not have ANY roles configured on the v2 authority"
        );
        assertEq(
            v2RolesAuthority.getUserRoles(address(v1Teller)),
            bytes32(0),
            "v1 Teller should not have ANY roles configured on the v2 authority"
        );
        assertEq(
            v2RolesAuthority.getUserRoles(address(v1Accountant)),
            bytes32(0),
            "v1 Accountant should not have ANY roles configured on the v2 authority"
        );

        // ============================================ V1 MANAGER WITH MERKLE VERIFICATION
        // ============================================

        // Check setManageRoot capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Manager), ManagerWithMerkleVerification.setManageRoot.selector
            ),
            "v1 ManagerWithMerkleVerification setManageRoot should NOT be public"
        );

        // Check pause capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Manager), ManagerWithMerkleVerification.pause.selector),
            "v1 ManagerWithMerkleVerification pause should NOT be public"
        );

        // Check unpause capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Manager), ManagerWithMerkleVerification.unpause.selector),
            "v1 ManagerWithMerkleVerification unpause should NOT be public"
        );

        // Check manageVaultWithMerkleVerification capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Manager), ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector
            ),
            "v1 ManagerWithMerkleVerification manageVaultWithMerkleVerification should NOT be public"
        );

        // Check flashLoan capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Manager), ManagerWithMerkleVerification.flashLoan.selector),
            "v1 ManagerWithMerkleVerification flashLoan should NOT be public"
        );

        // Check receiveFlashLoan capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Manager), ManagerWithMerkleVerification.receiveFlashLoan.selector
            ),
            "v1 ManagerWithMerkleVerification receiveFlashLoan should NOT be public"
        );

        // ============================================ V1 ACCOUNTANT WITH RATE PROVIDERS
        // ============================================

        // Check setRateProviderConfig capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Accountant), AccountantWithRateProviders.setRateProviderConfig.selector
            ),
            "v1 AccountantWithRateProviders setRateProviderConfig should NOT be public"
        );

        // Check pause capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Accountant), AccountantWithRateProviders.pause.selector),
            "v1 AccountantWithRateProviders pause should NOT be public"
        );

        // Check unpause capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Accountant), AccountantWithRateProviders.unpause.selector),
            "v1 AccountantWithRateProviders unpause should NOT be public"
        );

        // Check updateDelay capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Accountant), AccountantWithRateProviders.updateDelay.selector),
            "v1 AccountantWithRateProviders updateDelay should NOT be public"
        );

        // Check updateUpper capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Accountant), AccountantWithRateProviders.updateUpper.selector),
            "v1 AccountantWithRateProviders updateUpper should NOT be public"
        );

        // Check updateLower capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Accountant), AccountantWithRateProviders.updateLower.selector),
            "v1 AccountantWithRateProviders updateLower should NOT be public"
        );

        // Check updateManagementFee capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Accountant), AccountantWithRateProviders.updateManagementFee.selector
            ),
            "v1 AccountantWithRateProviders updateManagementFee should NOT be public"
        );

        // Check updatePerformanceFee capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Accountant), AccountantWithRateProviders.updatePerformanceFee.selector
            ),
            "v1 AccountantWithRateProviders updatePerformanceFee should NOT be public"
        );

        // Check updatePayoutAddress capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Accountant), AccountantWithRateProviders.updatePayoutAddress.selector
            ),
            "v1 AccountantWithRateProviders updatePayoutAddress should NOT be public"
        );

        // Check resetHighestExchangeRate capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Accountant), AccountantWithRateProviders.resetHighestExchangeRate.selector
            ),
            "v1 AccountantWithRateProviders resetHighestExchangeRate should NOT be public"
        );

        // Check updateExchangeRate capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Accountant), AccountantWithRateProviders.updateExchangeRate.selector
            ),
            "v1 AccountantWithRateProviders updateExchangeRate should NOT be public"
        );

        // Check claimFees capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Accountant), AccountantWithRateProviders.claimFees.selector),
            "v1 AccountantWithRateProviders claimFees should NOT be public"
        );

        // Check getDepositRate capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Accountant), AccountantWithRateProviders.getDepositRate.selector
            ),
            "v1 AccountantWithRateProviders getDepositRate should NOT be public"
        );

        // Check getLastUpdateTimestamp capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Accountant), AccountantWithRateProviders.getLastUpdateTimestamp.selector
            ),
            "v1 AccountantWithRateProviders getLastUpdateTimestamp should NOT be public"
        );

        // Check getSharesForDepositAmount capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Accountant), AccountantWithRateProviders.getSharesForDepositAmount.selector
            ),
            "v1 AccountantWithRateProviders getSharesForDepositAmount should NOT be public"
        );

        // Check getAssetsOutForShares capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Accountant), AccountantWithRateProviders.getAssetsOutForShares.selector
            ),
            "v1 AccountantWithRateProviders getAssetsOutForShares should NOT be public"
        );

        // Check getWithdrawRate capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Accountant), AccountantWithRateProviders.getWithdrawRate.selector
            ),
            "v1 AccountantWithRateProviders getWithdrawRate should NOT be public"
        );

        // Check isPaused capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Accountant), AccountantWithRateProviders.isPaused.selector),
            "v1 AccountantWithRateProviders isPaused should NOT be public"
        );

        // ============================================ V1 TELLER WITH MULTI ASSET SUPPORT
        // ============================================

        // Check setSupplyCap capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Teller), TellerWithMultiAssetSupport.setSupplyCap.selector),
            "v1 TellerWithMultiAssetSupport setSupplyCap should NOT be public"
        );

        // Check setMaxTimeFromLastUpdate capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Teller), TellerWithMultiAssetSupport.setMaxTimeFromLastUpdate.selector
            ),
            "v1 TellerWithMultiAssetSupport setMaxTimeFromLastUpdate should NOT be public"
        );

        // Check pause capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Teller), TellerWithMultiAssetSupport.pause.selector),
            "v1 TellerWithMultiAssetSupport pause should NOT be public"
        );

        // Check unpause capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Teller), TellerWithMultiAssetSupport.unpause.selector),
            "v1 TellerWithMultiAssetSupport unpause should NOT be public"
        );

        // Check setRateLimitPeriod capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Teller), TellerWithMultiAssetSupport.setRateLimitPeriod.selector
            ),
            "v1 TellerWithMultiAssetSupport setRateLimitPeriod should NOT be public"
        );

        // Check addAssets capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Teller), TellerWithMultiAssetSupport.addAssets.selector),
            "v1 TellerWithMultiAssetSupport addAssets should NOT be public"
        );

        // Check setShareLockPeriod capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Teller), TellerWithMultiAssetSupport.setShareLockPeriod.selector
            ),
            "v1 TellerWithMultiAssetSupport setShareLockPeriod should NOT be public"
        );

        // Check refundDeposit capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Teller), TellerWithMultiAssetSupport.refundDeposit.selector),
            "v1 TellerWithMultiAssetSupport refundDeposit should NOT be public"
        );

        // Check deposit capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Teller), TellerWithMultiAssetSupport.deposit.selector),
            "v1 TellerWithMultiAssetSupport deposit should NOT be public"
        );

        // Check depositWithPermit capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(
                address(v1Teller), TellerWithMultiAssetSupport.depositWithPermit.selector
            ),
            "v1 TellerWithMultiAssetSupport depositWithPermit should NOT be public"
        );

        // Check bulkWithdraw capability is NOT public for v1
        assertFalse(
            v2RolesAuthority.isCapabilityPublic(address(v1Teller), TellerWithMultiAssetSupport.bulkWithdraw.selector),
            "v1 TellerWithMultiAssetSupport bulkWithdraw should NOT be public"
        );
    }

    function testBaseAssetV1AndV2AreEqual() external {
        assertEq(address(v1Accountant.base()), address(v2Accountant.base()), "V1 and V2 base assets differ");
    }

    function testVaultIsSetInV2ContractsCorrectly() external {
        assertEq(address(v1Accountant.vault()), address(v2Accountant.vault()), "V1 and V2 vaults in Accountant differ");
        assertEq(address(v1Teller.vault()), address(v2Teller.vault()), "V1 and V2 vaults in Teller differ");
        assertEq(address(v1Manager.vault()), address(v2Manager.vault()), "V1 and V2 vaults in Manager differ");
    }

    function testBalancerVaultIsUnchanged() external {
        assertEq(
            address(v1Manager.balancerVault()),
            address(v2Manager.balancerVault()),
            "V1 and V2 balancer vaults in Manager differ"
        );
    }

    function testAccountantStateV1AndV2AreEqualExcludingPauseStatus() external {
        assertEq(
            _hashAccountantState(v1Accountant),
            _hashAccountantState(v2Accountant),
            "Hashes of V1 and V2 accountant data do not match"
        );
    }

    function testManageWithMerkleVerification() external {
        // Allow the manager to call the USDC approve function to a specific address,
        // and the USDT transfer function to a specific address.
        address usdcSpender = vm.addr(0xDEAD);
        address usdtTo = vm.addr(0xDEAD1);
        ManageLeaf[] memory leafs = new ManageLeaf[](2);
        leafs[0] = ManageLeaf(address(USDC), false, "approve(address,uint256)", new address[](1));
        leafs[0].argumentAddresses[0] = usdcSpender;
        leafs[1] = ManageLeaf(address(USDT), false, "approve(address,uint256)", new address[](1));
        leafs[1].argumentAddresses[0] = usdtTo;

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);

        v2Manager.setManageRoot(address(this), manageTree[1][0]);

        address[] memory targets = new address[](2);
        targets[0] = address(USDC);
        targets[1] = address(USDT);

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSelector(ERC20.approve.selector, usdcSpender, 777);
        targetData[1] = abi.encodeWithSelector(ERC20.approve.selector, usdtTo, 777);

        (bytes32[][] memory manageProofs) = _getProofsUsingTree(leafs, manageTree);

        uint256[] memory values = new uint256[](2);

        deal(address(USDT), address(boringVault), 777);

        address[] memory decodersAndSanitizers = new address[](2);
        decodersAndSanitizers[0] = rawDataDecoderAndSanitizer;
        decodersAndSanitizers[1] = rawDataDecoderAndSanitizer;

        uint256 gas = gasleft();
        v2Manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
        console.log("Gas used", gas - gasleft());

        assertEq(USDC.allowance(address(boringVault), usdcSpender), 777, "USDC should have an allowance");
        assertEq(USDT.allowance(address(boringVault), usdtTo), 777, "USDT should have have an allowance");
    }

    function testManageWithNoVerification() external { }

    // =========== Helper Functions ================
    function _depositAssetWithApprove(ERC20 asset, uint256 depositAmount) internal {
        deal(address(asset), address(this), depositAmount);
        asset.approve(address(boringVault), depositAmount);
        TellerWithMultiAssetSupport(v2Teller).deposit(asset, depositAmount, 0, address(this));
    }

    function _updateRate(uint96 rateChange, AccountantWithRateProviders accountant) internal {
        // update the rate
        // Prank the multisig for this for simplicity instead of a dedicated bot
        vm.startPrank(multisig);
        uint96 newRate = uint96(accountant.getRate()) * rateChange / 10_000;
        accountant.updateExchangeRate(newRate);
        vm.stopPrank();
    }

    function _startFork(string memory rpcKey) internal virtual returns (uint256 forkId) {
        if (block.chainid == 31_337) {
            forkId = vm.createFork(vm.envString(rpcKey));
            vm.selectFork(forkId);
        }
    }

    function _hashAccountantState(AccountantWithRateProviders accountant) internal returns (bytes32) {
        (
            address v1PayoutAddress,
            , // Skip fees owed
            , // Skip TotalSharesLastUpdate
            uint96 v1ExchangeRate,
            uint96 v1HighestExchangeRate,
            uint16 v1AllowedExchangeRateChangeUpper,
            uint16 v1AllowedExchangeRateChangeLower,
            , // Skip last update timestamp
            , // Skip isPaused
            uint32 v1MinimumUpdateDelayInSeconds,
            uint16 v1ManagementFee,
            uint16 v1PerformanceFee
        ) = accountant.accountantState();
        return keccak256(
            abi.encodePacked(
                v1PayoutAddress,
                v1ExchangeRate,
                v1HighestExchangeRate,
                v1AllowedExchangeRateChangeUpper,
                v1AllowedExchangeRateChangeLower,
                v1MinimumUpdateDelayInSeconds,
                v1ManagementFee,
                v1PerformanceFee
            )
        );
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
            leafs[0][i] = keccak256(bytes.concat(keccak256(rawDigest)));
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
            // Generate manage proof.
            bytes4 selector = bytes4(keccak256(abi.encodePacked(manageLeafs[i].signature)));
            bytes memory rawDigest = abi.encodePacked(
                rawDataDecoderAndSanitizer, manageLeafs[i].target, manageLeafs[i].canSendValue, selector
            );
            uint256 argumentAddressesLength = manageLeafs[i].argumentAddresses.length;
            for (uint256 j; j < argumentAddressesLength; ++j) {
                rawDigest = abi.encodePacked(rawDigest, manageLeafs[i].argumentAddresses[j]);
            }
            bytes32 leaf = keccak256(bytes.concat(keccak256(rawDigest)));
            proofs[i] = _generateProof(leaf, tree);
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

    function _generateProof(bytes32 leaf, bytes32[][] memory tree) internal pure returns (bytes32[] memory proof) {
        proof = new bytes32[](tree.length - 1);
        for (uint256 i; i < tree.length - 1; ++i) {
            for (uint256 j; j < tree[i].length; ++j) {
                if (tree[i][j] == leaf) {
                    // We have found the leaf, so now figure out if the proof needs the next leaf or the previous one.
                    proof[i] = j % 2 == 0 ? tree[i][j + 1] : tree[i][j - 1];
                    leaf = _hashPair(leaf, proof[i]);
                    break;
                }
            }
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
