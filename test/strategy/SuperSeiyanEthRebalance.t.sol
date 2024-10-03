pragma solidity 0.8.21;

import { StrategyBase, Leaf } from "./StrategyBase.t.sol";
import { NativeWrapperDecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/NativeWrapperDecoderAndSanitizer.sol";
import {
    SeiyanEthRebalanceDecoderAndSanitizer,
    BaseDecoderAndSanitizer,
    NativeWrapperDecoderAndSanitizer,
    ERC4626DecoderAndSanitizer,
    CurveDecoderAndSanitizer,
    LidoDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/SeiyanEthRebalanceDecoderAndSanitizer.sol";

import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { console } from "@forge-std/Test.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC4626 } from "@solmate/tokens/ERC4626.sol";

address constant ADMIN = 0x0000000000417626Ef34D62C4DC189b021603f2F;
address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant APX_ETH = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;
address constant PX_ETH = 0x04C154b66CB340F3Ae24111CC767e0184Ed00Cc6;
address constant PIREX_ETH = 0xD664b74274DfEB538d9baC494F3a4760828B02b0;
address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
address constant stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

address constant CURVE_pufETH = 0xEEda34A377dD0ca676b9511EE1324974fA8d980D;
uint256 constant ACCEPTED_CURVE_RECEIVE_pufETH_4_wstETH = 268.541877354420659066e18;
uint256 constant ACCEPTED_CURVE_RECEIVE_pxETH_4_stETH = 0;
uint256 constant TARGET_APX_ETH = 235.2211814e18;

contract SeiyanEthRebalanceStrategyTest is StrategyBase {
    using Address for address;

    ERC20 base = ERC20(WETH);
    ManagerWithMerkleVerification manager = ManagerWithMerkleVerification(0xCaF6FC6BAb79A32a1169Cb6A35bFa1d6B8551Bd2);
    BoringVault boringVault = BoringVault(payable(0xA8A3A5013104e093245164eA56588DBE10a3Eb48));
    SeiyanEthRebalanceDecoderAndSanitizer decoder;

    function setUp() public override {
        uint256 forkId = vm.createFork(vm.envString("L1_RPC_URL"));
        vm.selectFork(forkId);
        super.setUp();
    }

    function setUpDecoderSanitizers() public override {
        decoder = SeiyanEthRebalanceDecoderAndSanitizer(0x08dAbeAC71bcA6987Ec314cE0E532De4b96962b1);
    }

    function testRebalance() public {
        uint256 vaultBalance = base.balanceOf(address(boringVault));

        // DEPLOY: remove this after sending over eth
        deal(address(boringVault), 180_101_536_000_000_000_000);
        uint256 wethBal = address(boringVault).balance + vaultBalance;

        // construct leafs
        Leaf[] memory myLeafs = new Leaf[](5);

        // calldata for leafs
        bytes32[][] memory manageProofs = new bytes32[][](5);
        address[] memory decodersAndSanitizers = new address[](5);
        address[] memory targets = new address[](5);
        bytes[] memory targetData = new bytes[](5);
        uint256[] memory values = new uint256[](5);

        // leaf 0 = deposit eth into WETH native wrapper
        bytes memory packedArguments = "";
        myLeafs[0] =
            Leaf(address(decoder), WETH, true, NativeWrapperDecoderAndSanitizer.deposit.selector, packedArguments);
        // leaf 0 Calldata
        decodersAndSanitizers[0] = myLeafs[0].decoderAndSanitizer;
        targets[0] = myLeafs[0].target;
        targetData[0] = abi.encodeWithSelector(myLeafs[0].selector, "");
        values[0] = vaultBalance;

        // leaf 1 = approve curve to spend pufETH
        uint256 pufETHBal = ERC20(pufETH);
        packedArguments = abi.encodePacked(CURVE_pufETH);
        myLeafs[1] = Leaf(address(decoder), WETH, false, BaseDecoderAndSanitizer.approve.selector, packedArguments);
        // leaf 1 Calldata
        decodersAndSanitizers[1] = myLeafs[1].decoderAndSanitizer;
        targets[1] = myLeafs[1].target;
        targetData[1] = abi.encodeWithSelector(myLeafs[1].selector, CURVE_pufETH, pufETHBal);
        values[1] = 0;

        // leaf 2 = call Curve exchange pufETH -> wstETH
        int128 i = 0; // index of coin to send      [pufETH]
        int128 j = 1; // index of coin to receive   [wstETH]
        packedArguments = "";
        myLeafs[2] =
            Leaf(address(decoder), CURVE_pufETH, false, CurveDecoderAndSanitizer.exchange.selector, packedArguments);
        // leaf 2 Calldata
        decodersAndSanitizers[2] = myLeafs[2].decoderAndSanitizer;
        targets[2] = myLeafs[2].target;
        targetData[2] =
            abi.encodeWithSelector(myLeafs[2].selector, i, j, pufETHBal, ACCEPTED_CURVE_RECEIVE_pufETH_4_wstETH);
        values[2] = 0;

        // leaf 3 = unwrap wstETH
        uint256 wstETHBalance = ERC20(wstETH).balanceOf(address(boringVault));
        packedArguments = "";
        myLeafs[3] = Leaf(address(decoder), wstETH, false, LidoDecoderAndSanitizer.unwrap.selector, packedArguments);
        decodersAndSanitizers[3] = myLeafs[3].decoderAndSanitizer;
        targets[3] = myLeafs[3].target;
        targetData[3] = abi.encodeWithSelector(myLeafs[3].selector, wstETHBalance);
        values[3] = 0;

        // Leaf 4 = approve curve to spend stETH

        // Leaf 5 = call Curve exchange stETH -> pxETH

        // Leaf 6 = approve curve to spend weth [double with later approval to spend "rest of" weth for amount (10)]

        // Leaf 7 = call Curve exchange weth -> pxETH (target amount?)

        // leaf 8 = approve apxETH to spend all pxETH
        packedArguments = abi.encodePacked(APX_ETH);
        myLeafs[8] = Leaf(address(decoder), PX_ETH, false, BaseDecoderAndSanitizer.approve.selector, packedArguments);
        // leaf 8 Calldata
        decodersAndSanitizers[8] = myLeafs[8].decoderAndSanitizer;
        targets[8] = myLeafs[8].target;
        targetData[8] = abi.encodeWithSelector(myLeafs[3].selector, APX_ETH, ACCEPTED_CURVE_RECEIVE_pxETH_4_stETH);
        values[8] = 0;

        // leaf 9 = ERC4626 deposit on apxETH with pxETH
        packedArguments = abi.encodePacked(address(boringVault));
        myLeafs[9] =
            Leaf(address(decoder), APX_ETH, false, ERC4626DecoderAndSanitizer.deposit.selector, packedArguments);
        // leaf 9 Calldata
        decodersAndSanitizers[9] = myLeafs[9].decoderAndSanitizer;
        targets[9] = myLeafs[9].target;
        targetData[9] =
            abi.encodeWithSelector(myLeafs[9].selector, ACCEPTED_CURVE_RECEIVE_pxETH_4_stETH, address(boringVault));
        values[9] = 0;

        // leaf 10 = call Curve exchange weth -> frxETH (remaining?) NO LEAF, ONLY CALLDATA

        // leaf 11 = approve sfrxETH to spend frxETH

        // leaf 12 = deposit on sfrxETH with frxETH

        // console.log("myLeafs[0]");
        // console.log(myLeafs[0].decoderAndSanitizer);
        // console.log(myLeafs[0].target);
        // console.logBytes(myLeafs[0].packedArgumentAddresses);
        // console.logBytes4(myLeafs[0].selector);
        // console.log(myLeafs[0].valueNonZero);
        // console.log("targetData[0]");
        // console.log(decodersAndSanitizers[0]);
        // console.log(targets[0]);
        // console.logBytes(targetData[0]);
        // console.log(values[0]);
        // console.log("As _verifyManageProof");
        // bytes memory vmp_packedArgumentAddresses =
        // abi.decode((decodersAndSanitizers[0]).functionStaticCall(targetData[0]), (bytes));
        // console.log(decodersAndSanitizers[0]);
        // console.log(targets[0]);
        // console.log(values[0]);
        // console.logBytes4(bytes4(targetData[0]));
        // console.logBytes(vmp_packedArgumentAddresses);

        vm.startPrank(ADMIN);
        // admin allows strategy for deposit to APX ETH returning tokens to boring vault
        buildExampleTree(myLeafs);
        manageProofs = _getProofsUsingTree(myLeafs, tree);
        manager.setManageRoot(ADMIN, _getRoot());
        assertEq(manager.manageRoot(ADMIN), _getRoot(), "Root not set correctly");

        console.log("ROOT:");
        console.logBytes32(_getRoot());
        _logManageVaultWithMerkleVerification(manager, manageProofs, decodersAndSanitizers, targets, targetData, values);

        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
        assertGe(ERC20(APX_ETH).balanceOf(address(boringVault)), TARGET_APX_ETH, "APX_ETH balance is less than target");
        vm.stopPrank();

        uint256 pxETHValueOfAssets = ERC4626(APX_ETH).previewRedeem(ERC20(APX_ETH).balanceOf(address(boringVault)));
        console.log(pxETHValueOfAssets);
        console.log(ERC20(APX_ETH).balanceOf(address(boringVault)));
        assertGe(pxETHValueOfAssets, wethBal, "Should get back more APX_ETH than WETH");
    }

    function _setUpManager(uint256 depositAmount) internal { }
}
