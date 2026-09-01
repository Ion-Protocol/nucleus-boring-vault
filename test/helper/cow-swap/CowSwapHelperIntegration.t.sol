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

/// @notice Minimal mintable ERC20 with configurable decimals.
contract MockERC20 is ERC20 {

    constructor(string memory n, string memory s, uint8 d) ERC20(n, s, d) { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

}

/// @notice Fixed-price rate provider so the floor is deterministic without a live oracle.
contract FixedRateProvider is IRateProvider {

    uint256 internal immutable rate;

    constructor(uint256 _rate) {
        rate = _rate;
    }

    function getRate() external view returns (uint256) {
        return rate;
    }

}

/// @notice Stand-in for CoW's settlement: records pre-signatures and enforces the owner-is-caller rule the
///         helper relies on, and exposes the two immutables the helper caches at deploy.
contract MockSettlement is IGPv2Settlement {

    address public immutable vaultRelayer;
    bytes32 public immutable domainSeparator;

    mapping(bytes => bool) public isSigned;

    constructor(address _vaultRelayer, bytes32 _domainSeparator) {
        vaultRelayer = _vaultRelayer;
        domainSeparator = _domainSeparator;
    }

    function setPreSignature(bytes calldata orderUid, bool signed) external {
        // Mirrors GPv2Signing: the owner packed into the UID must be the caller. This is the invariant that
        // forces the helper (not the vault) to be the order owner.
        require(orderUid.length == 56, "MockSettlement: bad uid length");
        address uidOwner = address(bytes20(orderUid[32:52]));
        require(uidOwner == msg.sender, "GPv2: caller does not own order");
        isSigned[orderUid] = signed;
    }

}

/// @notice Concrete decoder exposing only the CowSwap surface for this test.
contract CowSwapTestDecoderAndSanitizer is CowSwapHelperDecoderAndSanitizer {

    constructor(address _boringVault) BaseDecoderAndSanitizer(_boringVault) { }

}

/// @notice Integration tests exercising the full strategist path - ManagerWithMerkleVerification -> BoringVault
///         -> CowSwapHelper -> settlement - against the current helper, which owns each order itself and holds
///         the sell-token collateral in its own balance (returned to the vault via `sweepToken`).
/// @dev The settlement, rate provider, and tokens are mocked so the suite runs without a mainnet fork; the
///      vault, manager, decoder, roles authority, and merkle verification are all the real contracts.
contract CowSwapHelperIntegrationTest is Test {

    uint8 internal constant MANAGER_ROLE = 1;
    uint8 internal constant STRATEGIST_ROLE = 2;

    // 3000 buyToken per 1 sellToken, expressed as an 18-decimal rate.
    uint256 internal constant RATE_18 = 3000e18;
    uint8 internal constant RATE_DECIMALS = 18;
    uint256 internal constant MAX_SLIPPAGE_BPS = 100; // 1%
    uint256 internal constant SELL_AMOUNT = 10e18; // 10 sellToken (18 decimals)
    uint32 internal constant MAX_ORDER_VALIDITY = 1 days;
    uint256 internal constant BUY_AMOUNT = 29_700e6; // 10 * 3000 * 0.99 = floor at 1% slippage (buyToken has 6 dp)

    bytes32 internal constant DOMAIN_SEPARATOR = keccak256("test-domain-separator");

    BoringVault internal boringVault;
    ManagerWithMerkleVerification internal manager;
    RolesAuthority internal rolesAuthority;
    CowSwapTestDecoderAndSanitizer internal decoder;
    CowSwapHelper internal helper;
    MockSettlement internal settlement;
    FixedRateProvider internal rateProvider;
    MockERC20 internal sellToken; // 18 decimals
    MockERC20 internal buyToken; // 6 decimals

    address internal relayer = makeAddr("relayer");
    address internal strategist = makeAddr("strategist");

    // Cached merkle material. sweepToken is merkle-gated (onlyBoringVault) and so also has a leaf.
    bytes32[][] internal tree;
    bytes32 internal approveLeaf;
    bytes32 internal placeLeaf;
    bytes32 internal cancelLeaf;
    bytes32 internal sweepLeaf;

    function setUp() external {
        settlement = new MockSettlement(relayer, DOMAIN_SEPARATOR);
        rateProvider = new FixedRateProvider(RATE_18);
        sellToken = new MockERC20("Sell", "SELL", 18);
        buyToken = new MockERC20("Buy", "BUY", 6);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 18);
        manager = new ManagerWithMerkleVerification(address(this), address(boringVault), address(0));
        decoder = new CowSwapTestDecoderAndSanitizer(address(boringVault));
        helper = new CowSwapHelper(address(this), address(boringVault), address(settlement), MAX_ORDER_VALIDITY);

        _wireRolesAuthority();
        _buildAndSetRoot(false);
    }

    // ------------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------------

    /// @dev Approve + placeOrder in one merkle-verified batch, then check the settlement pre-signed the UID and
    ///      the sell token moved from the vault into the helper (which custodies it, not a proxy).
    function test_placeOrder_presignsThroughMerklePath() external {
        sellToken.mint(address(boringVault), SELL_AMOUNT);

        bytes memory uid = _expectedUid(BUY_AMOUNT, false);
        _approveAndPlace(BUY_AMOUNT, false);

        assertTrue(settlement.isSigned(uid), "order pre-signed on settlement");
        assertEq(sellToken.balanceOf(address(helper)), SELL_AMOUNT, "helper custodies the sell token");
        assertEq(sellToken.balanceOf(address(boringVault)), 0, "vault moved the sell token out");
        assertEq(
            sellToken.allowance(address(helper), relayer), type(uint256).max, "relayer approved to pull from the helper"
        );
        assertEq(sellToken.allowance(address(boringVault), address(helper)), 0, "no dangling vault allowance");
    }

    /// @dev A cancel batch clears the settlement pre-signature; a following sweepToken batch returns the unfilled
    ///      collateral from the helper to the vault (the helper keeps no fill accounting, so the sweep is separate).
    function test_cancelOrder_thenSweep_returnsFundsToVault() external {
        sellToken.mint(address(boringVault), SELL_AMOUNT);
        bytes memory uid = _expectedUid(BUY_AMOUNT, false);
        _approveAndPlace(BUY_AMOUNT, false);
        assertTrue(settlement.isSigned(uid), "precondition: signed");

        _manageSingle(cancelLeaf, address(helper), abi.encodeWithSelector(CowSwapHelper.cancelOrder.selector, uid));
        assertFalse(settlement.isSigned(uid), "pre-signature cleared");
        assertEq(sellToken.balanceOf(address(helper)), SELL_AMOUNT, "collateral still with helper until swept");

        _manageSingle(
            sweepLeaf,
            address(helper),
            abi.encodeWithSelector(CowSwapHelper.sweepToken.selector, address(sellToken), SELL_AMOUNT)
        );
        assertEq(sellToken.balanceOf(address(helper)), 0, "helper swept");
        assertEq(sellToken.balanceOf(address(boringVault)), SELL_AMOUNT, "vault made whole on sweep");
    }

    /// @dev partiallyFillable = true is honored end-to-end: the resulting (distinct) UID is pre-signed.
    function test_placeOrder_partiallyFillable_presigns() external {
        sellToken.mint(address(boringVault), SELL_AMOUNT);
        bytes memory uid = _expectedUid(BUY_AMOUNT, true);

        // Rebuild the tree with a partiallyFillable = true placeOrder leaf so it is authorized.
        _buildAndSetRoot(true);
        _approveAndPlace(BUY_AMOUNT, true);

        assertTrue(settlement.isSigned(uid), "partial-fill order pre-signed");
    }

    /// @dev The merkle leaf pins the rate provider: a placeOrder pointing at a different provider fails
    ///      verification before ever reaching the helper. This is the on-chain gate the helper relies on.
    function test_placeOrder_unpinnedRateProvider_failsVerification() external {
        sellToken.mint(address(boringVault), SELL_AMOUNT);
        FixedRateProvider rogueProvider = new FixedRateProvider(RATE_18);

        CowSwapHelper.OrderParams memory p = _params(BUY_AMOUNT, false);
        p.rateProvider = IRateProvider(address(rogueProvider)); // not the pinned provider

        bytes memory placeData = abi.encodeWithSelector(CowSwapHelper.placeOrder.selector, p);

        // Reuse the placeOrder proof; it will not verify against the rogue provider's decoded address.
        (
            bytes32[][] memory proofs,
            address[] memory decoders,
            address[] memory targets,
            bytes[] memory data,
            uint256[] memory values
        ) = _singleCall(placeLeaf, address(helper), placeData);

        vm.prank(strategist);
        vm.expectRevert(
            abi.encodeWithSelector(
                ManagerWithMerkleVerification.ManagerWithMerkleVerification__FailedToVerifyManageProof.selector,
                address(helper),
                placeData,
                uint256(0)
            )
        );
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, data, values);
    }

    /// @dev A buyAmount below the oracle-derived floor is rejected by the helper's own price check, bubbling up
    ///      through the merkle path (the leaf pins the oracle inputs but leaves the amounts free).
    function test_placeOrder_belowFloor_reverts() external {
        sellToken.mint(address(boringVault), SELL_AMOUNT);
        uint256 tooLow = BUY_AMOUNT - 1;

        (
            bytes32[][] memory proofs,
            address[] memory decoders,
            address[] memory targets,
            bytes[] memory data,
            uint256[] memory values
        ) = _approveAndPlaceCalls(tooLow, false);

        vm.prank(strategist);
        vm.expectRevert(); // helper reverts PriceTooLow; the exact floor is asserted in the unit suite
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, data, values);
    }

    // ------------------------------------------------------------------------
    // Flow helpers
    // ------------------------------------------------------------------------

    /// @dev Runs the approve + placeOrder pair through the manager in one verified batch.
    function _approveAndPlace(uint256 buyAmount, bool partiallyFillable) internal {
        (
            bytes32[][] memory proofs,
            address[] memory decoders,
            address[] memory targets,
            bytes[] memory data,
            uint256[] memory values
        ) = _approveAndPlaceCalls(buyAmount, partiallyFillable);

        vm.prank(strategist);
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, data, values);
    }

    /// @dev Builds the approve + placeOrder batch arguments (without executing) so callers can also assert reverts.
    function _approveAndPlaceCalls(
        uint256 buyAmount,
        bool partiallyFillable
    )
        internal
        view
        returns (
            bytes32[][] memory proofs,
            address[] memory decoders,
            address[] memory targets,
            bytes[] memory data,
            uint256[] memory values
        )
    {
        CowSwapHelper.OrderParams memory p = _params(buyAmount, partiallyFillable);

        proofs = new bytes32[][](2);
        proofs[0] = _proof(approveLeaf);
        proofs[1] = _proof(_placeLeaf(partiallyFillable));

        decoders = new address[](2);
        decoders[0] = address(decoder);
        decoders[1] = address(decoder);

        targets = new address[](2);
        targets[0] = address(sellToken);
        targets[1] = address(helper);

        data = new bytes[](2);
        data[0] = abi.encodeWithSelector(ERC20.approve.selector, address(helper), SELL_AMOUNT);
        data[1] = abi.encodeWithSelector(CowSwapHelper.placeOrder.selector, p);

        values = new uint256[](2);
    }

    /// @dev Runs a single authorized call through the manager.
    function _manageSingle(bytes32 leaf, address target, bytes memory callData) internal {
        (
            bytes32[][] memory proofs,
            address[] memory decoders,
            address[] memory targets,
            bytes[] memory data,
            uint256[] memory values
        ) = _singleCall(leaf, target, callData);

        vm.prank(strategist);
        manager.manageVaultWithMerkleVerification(proofs, decoders, targets, data, values);
    }

    /// @dev Builds single-call batch arguments for `leaf`/`target`/`callData`.
    function _singleCall(
        bytes32 leaf,
        address target,
        bytes memory callData
    )
        internal
        view
        returns (
            bytes32[][] memory proofs,
            address[] memory decoders,
            address[] memory targets,
            bytes[] memory data,
            uint256[] memory values
        )
    {
        proofs = new bytes32[][](1);
        proofs[0] = _proof(leaf);
        decoders = new address[](1);
        decoders[0] = address(decoder);
        targets = new address[](1);
        targets[0] = target;
        data = new bytes[](1);
        data[0] = callData;
        values = new uint256[](1);
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
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: SELL_AMOUNT,
            buyAmount: buyAmount,
            validTo: uint32(block.timestamp + 1 hours),
            partiallyFillable: partiallyFillable,
            rateProvider: IRateProvider(address(rateProvider)),
            rateDecimals: RATE_DECIMALS,
            maxSlippageBps: MAX_SLIPPAGE_BPS
        });
    }

    /// @dev Rebuilds the order digest the helper will sign; owner is the helper itself.
    function _expectedUid(uint256 buyAmount, bool partiallyFillable) internal view returns (bytes memory) {
        CowSwapOrderLib.Data memory order = CowSwapOrderLib.Data({
            sellToken: address(sellToken),
            buyToken: address(buyToken),
            receiver: address(boringVault),
            sellAmount: SELL_AMOUNT,
            buyAmount: buyAmount,
            validTo: uint32(block.timestamp + 1 hours),
            appData: bytes32(0),
            feeAmount: 0,
            kind: CowSwapOrderLib.KIND_SELL,
            partiallyFillable: partiallyFillable,
            sellTokenBalance: CowSwapOrderLib.BALANCE_ERC20,
            buyTokenBalance: CowSwapOrderLib.BALANCE_ERC20
        });
        bytes32 digest = CowSwapOrderLib.hash(order, DOMAIN_SEPARATOR);
        return CowSwapOrderLib.packOrderUid(digest, address(helper), uint32(block.timestamp + 1 hours));
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
            abi.encodePacked(address(decoder), address(sellToken), false, ERC20.approve.selector, address(helper))
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
                address(sellToken),
                address(buyToken),
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
