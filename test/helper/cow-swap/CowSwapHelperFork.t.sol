// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "@forge-std/Test.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";

import { BoringVault } from "src/base/BoringVault.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import {
    CowSwapHelperDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/Protocols/CowSwapHelperDecoderAndSanitizer.sol";
import { CowSwapHelper } from "src/helper/cow-swap/CowSwapHelper.sol";
import { CowSwapOrderLib } from "src/libraries/CowSwapOrderLib.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { IGPv2Settlement } from "src/interfaces/IGPv2Settlement.sol";

/// @notice Extended settlement view used only in tests: the public `preSignature` mapping getter, which the
///         minimal `IGPv2Settlement` interface omits. A non-zero value means the UID is pre-signed.
interface IGPv2SettlementExt {

    function preSignature(bytes calldata orderUid) external view returns (uint256);

}

/// @notice Concrete decoder exposing only the CowSwap surface for this test.
contract CowSwapForkDecoderAndSanitizer is CowSwapHelperDecoderAndSanitizer {

    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) { }

}

/// @notice Fixed-price rate provider so the floor is deterministic and independent of live oracles.
contract FixedRateProvider is IRateProvider {

    uint256 internal immutable rate;

    constructor(uint256 _rate) {
        rate = _rate;
    }

    function getRate() external view returns (uint256) {
        return rate;
    }

}

/// @notice Fork tests exercising the full strategist path - ManagerWithMerkleVerification -> BoringVault ->
///         CowSwapHelper -> the REAL CoW settlement - against a mainnet fork.
/// @dev Only the rate provider is mocked (an external oracle dependency); the settlement, its cached domain
///      separator and vault relayer, the pre-signature bookkeeping, and the ERC20s are all real. This is the
///      coverage the fork-free `CowSwapHelperIntegration.t.sol` cannot provide: that the helper's reconstructed
///      UID is actually accepted and recorded by CoW's own settlement contract. Requires `MAINNET_RPC_URL`.
contract CowSwapHelperForkTest is Test {

    // Real CoW Protocol GPv2Settlement on Ethereum mainnet.
    address internal constant COW_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    ERC20 internal constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 internal constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    uint256 internal constant FORK_BLOCK = 19_826_676;

    uint8 internal constant MANAGER_ROLE = 1;
    uint8 internal constant STRATEGIST_ROLE = 2;

    // 3000 USDC per WETH, expressed as an 18-decimal rate.
    uint256 internal constant RATE_18 = 3000e18;
    uint8 internal constant RATE_DECIMALS = 18;
    uint256 internal constant MAX_SLIPPAGE_BPS = 100; // 1%
    uint256 internal constant SELL_AMOUNT = 10e18; // 10 WETH
    uint32 internal constant MAX_ORDER_VALIDITY = 1 days;
    uint256 internal constant BUY_AMOUNT = 29_700e6; // 10 * 3000 * 0.99 = floor at 1% slippage

    BoringVault internal boringVault;
    ManagerWithMerkleVerification internal manager;
    RolesAuthority internal rolesAuthority;
    CowSwapForkDecoderAndSanitizer internal decoder;
    CowSwapHelper internal helper;
    FixedRateProvider internal rateProvider;

    address internal strategist = makeAddr("strategist");

    // Cached merkle material. sweepToken is merkle-gated (onlyBoringVault) and so also has a leaf.
    bytes32[][] internal tree;
    bytes32 internal approveLeaf;
    bytes32 internal placeLeaf;
    bytes32 internal cancelLeaf;
    bytes32 internal sweepLeaf;

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), FORK_BLOCK);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 18);
        manager = new ManagerWithMerkleVerification(address(this), address(boringVault), address(0));
        decoder = new CowSwapForkDecoderAndSanitizer(address(boringVault));
        rateProvider = new FixedRateProvider(RATE_18);
        helper = new CowSwapHelper(address(this), address(boringVault), COW_SETTLEMENT, MAX_ORDER_VALIDITY);

        _wireRolesAuthority();
        _buildAndSetRoot(false);
    }

    // ------------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------------

    /// @dev Approve + placeOrder in one merkle-verified batch, then check the real settlement pre-signed the UID
    ///      and the sell token moved from the vault into the helper (which custodies it, not a proxy).
    function test_placeOrder_presignsOnRealSettlement() external {
        deal(address(WETH), address(boringVault), SELL_AMOUNT);

        CowSwapHelper.OrderParams memory p = _params(BUY_AMOUNT, false);
        bytes memory uid = _expectedUid(p);
        _approveAndPlace(p);

        assertTrue(IGPv2SettlementExt(COW_SETTLEMENT).preSignature(uid) != 0, "order pre-signed on real settlement");
        assertEq(WETH.balanceOf(address(helper)), SELL_AMOUNT, "helper custodies the sell token");
        assertEq(WETH.balanceOf(address(boringVault)), 0, "vault moved the sell token out");
        assertEq(
            WETH.allowance(address(helper), IGPv2Settlement(COW_SETTLEMENT).vaultRelayer()),
            type(uint256).max,
            "real relayer approved to pull from the helper"
        );
    }

    /// @dev A cancel batch clears the pre-signature on the real settlement; a following sweepToken batch returns
    ///      the unfilled collateral from the helper to the vault.
    function test_cancelOrder_clearsPresignatureOnRealSettlement() external {
        deal(address(WETH), address(boringVault), SELL_AMOUNT);
        CowSwapHelper.OrderParams memory p = _params(BUY_AMOUNT, false);
        bytes memory uid = _expectedUid(p);
        _approveAndPlace(p);
        assertTrue(IGPv2SettlementExt(COW_SETTLEMENT).preSignature(uid) != 0, "precondition: signed");

        _manageSingle(cancelLeaf, address(helper), abi.encodeWithSelector(CowSwapHelper.cancelOrder.selector, uid));
        assertEq(IGPv2SettlementExt(COW_SETTLEMENT).preSignature(uid), 0, "pre-signature cleared on real settlement");

        _manageSingle(
            sweepLeaf,
            address(helper),
            abi.encodeWithSelector(CowSwapHelper.sweepToken.selector, address(WETH), SELL_AMOUNT)
        );
        assertEq(WETH.balanceOf(address(helper)), 0, "helper swept");
        assertEq(WETH.balanceOf(address(boringVault)), SELL_AMOUNT, "vault made whole on sweep");
    }

    // ------------------------------------------------------------------------
    // Flow helpers
    // ------------------------------------------------------------------------

    /// @dev Runs the approve + placeOrder pair through the manager in one verified batch.
    function _approveAndPlace(CowSwapHelper.OrderParams memory p) internal {
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = _proof(approveLeaf);
        proofs[1] = _proof(_placeLeaf(p.partiallyFillable));

        address[] memory decoders = new address[](2);
        decoders[0] = address(decoder);
        decoders[1] = address(decoder);

        address[] memory targets = new address[](2);
        targets[0] = address(WETH);
        targets[1] = address(helper);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(ERC20.approve.selector, address(helper), SELL_AMOUNT);
        data[1] = abi.encodeWithSelector(CowSwapHelper.placeOrder.selector, p);

        uint256[] memory values = new uint256[](2);

        vm.prank(strategist);
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, data, values);
    }

    /// @dev Runs a single authorized call through the manager.
    function _manageSingle(bytes32 leaf, address target, bytes memory callData) internal {
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = _proof(leaf);
        address[] memory decoders = new address[](1);
        decoders[0] = address(decoder);
        address[] memory targets = new address[](1);
        targets[0] = target;
        bytes[] memory data = new bytes[](1);
        data[0] = callData;
        uint256[] memory values = new uint256[](1);

        vm.prank(strategist);
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, data, values);
    }

    function _params(
        uint256 buyAmount,
        bool partiallyFillable
    )
        internal
        view
        returns (CowSwapHelper.OrderParams memory)
    {
        return CowSwapHelper.OrderParams({
            sellToken: WETH,
            buyToken: USDC,
            sellAmount: SELL_AMOUNT,
            buyAmount: buyAmount,
            validTo: uint32(block.timestamp + 1 hours),
            partiallyFillable: partiallyFillable,
            rateProvider: IRateProvider(address(rateProvider)),
            rateDecimals: RATE_DECIMALS,
            maxSlippageBps: MAX_SLIPPAGE_BPS
        });
    }

    /// @dev Rebuilds, against the REAL settlement's domain separator, the order digest the helper will sign;
    ///      owner is the helper itself.
    function _expectedUid(CowSwapHelper.OrderParams memory p) internal view returns (bytes memory) {
        CowSwapOrderLib.Data memory order = CowSwapOrderLib.Data({
            sellToken: address(p.sellToken),
            buyToken: address(p.buyToken),
            receiver: address(boringVault),
            sellAmount: p.sellAmount,
            buyAmount: p.buyAmount,
            validTo: p.validTo,
            appData: bytes32(0),
            feeAmount: 0,
            kind: CowSwapOrderLib.KIND_SELL,
            partiallyFillable: p.partiallyFillable,
            sellTokenBalance: CowSwapOrderLib.BALANCE_ERC20,
            buyTokenBalance: CowSwapOrderLib.BALANCE_ERC20
        });
        bytes32 digest = CowSwapOrderLib.hash(order, IGPv2Settlement(COW_SETTLEMENT).domainSeparator());
        return CowSwapOrderLib.packOrderUid(digest, address(helper), p.validTo);
    }

    // ------------------------------------------------------------------------
    // Roles + merkle setup
    // ------------------------------------------------------------------------

    function _wireRolesAuthority() internal {
        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        boringVault.setAuthority(rolesAuthority);
        manager.setAuthority(rolesAuthority);

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, address(boringVault), bytes4(keccak256("manage(address,bytes,uint256)")), true
        );
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE, address(boringVault), bytes4(keccak256("manage(address[],bytes[],uint256[])")), true
        );
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(manager),
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );

        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(strategist, STRATEGIST_ROLE, true);
    }

    /// @dev Builds the 4-leaf tree (approve, placeOrder, cancelOrder, sweepToken) and registers the root.
    function _buildAndSetRoot(bool partiallyFillable) internal {
        approveLeaf = keccak256(
            abi.encodePacked(address(decoder), address(WETH), false, ERC20.approve.selector, address(helper))
        );
        placeLeaf = _placeLeaf(partiallyFillable);
        cancelLeaf =
            keccak256(abi.encodePacked(address(decoder), address(helper), false, CowSwapHelper.cancelOrder.selector));
        sweepLeaf =
            keccak256(abi.encodePacked(address(decoder), address(helper), false, CowSwapHelper.sweepToken.selector));

        bytes32[][] memory leafs = new bytes32[][](1);
        leafs[0] = new bytes32[](4);
        leafs[0][0] = approveLeaf;
        leafs[0][1] = placeLeaf;
        leafs[0][2] = cancelLeaf;
        leafs[0][3] = sweepLeaf;

        tree = _buildTrees(leafs);
        manager.setManageRoot(strategist, tree[tree.length - 1][0]);
    }

    /// @dev The placeOrder leaf pins sellToken, buyToken, rateProvider, rateDecimals, maxSlippageBps, and the
    ///      partial-fill flag - exactly the bytes the decoder returns, in order.
    function _placeLeaf(bool partiallyFillable) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                address(decoder),
                address(helper),
                false,
                CowSwapHelper.placeOrder.selector,
                address(WETH),
                address(USDC),
                address(rateProvider),
                RATE_DECIMALS,
                MAX_SLIPPAGE_BPS,
                partiallyFillable
            )
        );
    }

    // ------------------------------------------------------------------------
    // Merkle primitives (mirror ManagerWithMerkleVerification's OpenZeppelin-style tree)
    // ------------------------------------------------------------------------

    function _proof(bytes32 leaf) internal view returns (bytes32[] memory proof) {
        uint256 treeLength = tree.length;
        proof = new bytes32[](treeLength - 1);
        for (uint256 i; i < treeLength - 1; ++i) {
            for (uint256 j; j < tree[i].length; ++j) {
                if (leaf == tree[i][j]) {
                    proof[i] = j % 2 == 0 ? tree[i][j + 1] : tree[i][j - 1];
                    leaf = _hashPair(leaf, proof[i]);
                    break;
                }
            }
        }
    }

    function _buildTrees(bytes32[][] memory merkleTreeIn) internal pure returns (bytes32[][] memory merkleTreeOut) {
        uint256 inLength = merkleTreeIn.length;
        merkleTreeOut = new bytes32[][](inLength + 1);
        uint256 layerLength;
        for (uint256 i; i < inLength; ++i) {
            layerLength = merkleTreeIn[i].length;
            merkleTreeOut[i] = new bytes32[](layerLength);
            for (uint256 j; j < layerLength; ++j) {
                merkleTreeOut[i][j] = merkleTreeIn[i][j];
            }
        }

        uint256 nextLayerLength = layerLength % 2 != 0 ? (layerLength + 1) / 2 : layerLength / 2;
        merkleTreeOut[inLength] = new bytes32[](nextLayerLength);
        uint256 count;
        for (uint256 i; i < layerLength; i += 2) {
            merkleTreeOut[inLength][count] = _hashPair(merkleTreeIn[inLength - 1][i], merkleTreeIn[inLength - 1][i + 1]);
            count++;
        }
        if (nextLayerLength > 1) {
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
