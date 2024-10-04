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
address constant pufETH = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
address constant stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
address constant frxETH = 0x5E8422345238F34275888049021821E8E08CAa1f;
address constant sfrxETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;

address constant CURVE_pufETH_wstETH = 0xEEda34A377dD0ca676b9511EE1324974fA8d980D;
address constant CURVE_pxETH_stETH = 0x6951bDC4734b9f7F3E1B74afeBC670c736A0EDB6;
address constant CURVE_pxETH_WETH = 0xC8Eb2Cf2f792F77AF0Cd9e203305a585E588179D;
address constant CURVE_frxETH_WETH = 0x9c3B46C0Ceb5B9e304FCd6D88Fc50f7DD24B31Bc;
uint256 constant ACCEPTED_CURVE_RECEIVE_pufETH_4_wstETH = 0;
uint256 constant ACCEPTED_CURVE_RECEIVE_pxETH_4_stETH = 0;
uint256 constant ACCEPTED_CURVE_RECEIVE_pxETH_4_WETH = 0;
uint256 constant ACCEPTED_CURVE_RECEIVE_frxETH_4_WETH = 0;

uint256 constant _0_WETH = 10 ether;
uint256 constant _1_pufETH = 1 ether;
uint256 constant _2_pufETH = 1 ether;
uint256 constant _3_wstETH = 0.5 ether;
uint256 constant _4_stETH = 0.5 ether;
uint256 constant _5_stETH = 0.5 ether;
uint256 constant _6_WETH = 1 ether;
uint256 constant _7_WETH = 0.5 ether;
uint256 constant _8_pxETH = 0.5 ether;
uint256 constant _9_pxETH = 0.5 ether;
uint256 constant _10_WETH = 1 ether;
uint256 constant _11_WETH = 0.5 ether;
uint256 constant _12_frxETH = 1 ether;
uint256 constant _13_frxETH = 1 ether;

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
        vm.prank(ADMIN);
        manager.unpause();
    }

    function testRebalance() public {
        uint256 vaultBalance = base.balanceOf(address(boringVault));
        // DEPLOY: remove this after sending over eth
        deal(address(boringVault), 180_101_536_000_000_000_000);
        uint256 wethBal = address(boringVault).balance + vaultBalance;

        Leaf[] memory myLeafs = new Leaf[](14);

        //=======================================================================================================================
        // Leaf Initialization
        // leaf 0 = deposit eth into WETH native wrapper
        bytes memory packedArguments = "";
        myLeafs[0] =
            Leaf(address(decoder), WETH, true, NativeWrapperDecoderAndSanitizer.deposit.selector, packedArguments);

        // leaf 1 = approve curve to spend pufETH
        packedArguments = abi.encodePacked(CURVE_pufETH_wstETH);
        myLeafs[1] = Leaf(address(decoder), pufETH, false, BaseDecoderAndSanitizer.approve.selector, packedArguments);

        // leaf 2 = call Curve exchange pufETH -> wstETH
        int128 i = 0; // index of coin to send      [pufETH]
        int128 j = 1; // index of coin to receive   [wstETH]
        packedArguments = "";
        myLeafs[2] = Leaf(
            address(decoder), CURVE_pufETH_wstETH, false, CurveDecoderAndSanitizer.exchange.selector, packedArguments
        );

        // leaf 3 = unwrap wstETH
        packedArguments = "";
        myLeafs[3] = Leaf(address(decoder), wstETH, false, LidoDecoderAndSanitizer.unwrap.selector, packedArguments);

        // Leaf 4 = approve curve to spend stETH
        packedArguments = abi.encodePacked(CURVE_pxETH_stETH);
        myLeafs[4] = Leaf(address(decoder), stETH, false, BaseDecoderAndSanitizer.approve.selector, packedArguments);

        // Leaf 5 = call Curve exchange stETH -> pxETH
        i = 1; // index of coin to send      [stETH]
        j = 0; // index of coin to receive   [pxETH]
        packedArguments = "";
        myLeafs[5] = Leaf(
            address(decoder), CURVE_pxETH_stETH, false, CurveDecoderAndSanitizer.exchange.selector, packedArguments
        );

        // Leaf 6 = approve curve to spend weth -> pxETH
        packedArguments = abi.encodePacked(CURVE_pxETH_WETH);
        myLeafs[6] = Leaf(address(decoder), WETH, false, BaseDecoderAndSanitizer.approve.selector, packedArguments);

        // Leaf 7 = call Curve exchange weth -> pxETH (target amount?)
        i = 0; // index of coin to send      [WETH]
        j = 1; // index of coin to receive   [pxETH]
        packedArguments = "";
        myLeafs[7] =
            Leaf(address(decoder), CURVE_pxETH_WETH, false, CurveDecoderAndSanitizer.exchange.selector, packedArguments);

        // leaf 8 = approve apxETH to spend all pxETH
        packedArguments = abi.encodePacked(APX_ETH);
        myLeafs[8] = Leaf(address(decoder), PX_ETH, false, BaseDecoderAndSanitizer.approve.selector, packedArguments);

        // leaf 9 = ERC4626 deposit on apxETH with pxETH
        packedArguments = abi.encodePacked(address(boringVault));
        myLeafs[9] =
            Leaf(address(decoder), APX_ETH, false, ERC4626DecoderAndSanitizer.deposit.selector, packedArguments);

        // leaf 10 = approve Curve to spent weth -> frxETH
        packedArguments = abi.encodePacked(CURVE_frxETH_WETH);
        myLeafs[10] = Leaf(address(decoder), WETH, false, BaseDecoderAndSanitizer.approve.selector, packedArguments);

        // leaf 11 = call Curve exchange weth -> frxETH (remaining?)
        i = 0; // index of coin to send      [WETH]
        j = 1; // index of coin to receive   [frxETH]
        packedArguments = "";
        myLeafs[11] = Leaf(
            address(decoder), CURVE_frxETH_WETH, false, CurveDecoderAndSanitizer.exchange.selector, packedArguments
        );

        // leaf 12 = approve sfrxETH to spend frxETH
        packedArguments = abi.encodePacked(sfrxETH);
        myLeafs[12] = Leaf(address(decoder), frxETH, false, BaseDecoderAndSanitizer.approve.selector, packedArguments);

        // leaf 13 = deposit on sfrxETH with frxETH
        packedArguments = abi.encodePacked(address(boringVault));
        myLeafs[13] =
            Leaf(address(decoder), sfrxETH, false, ERC4626DecoderAndSanitizer.deposit.selector, packedArguments);

        // Build tree and set root
        buildExampleTree(myLeafs);
        vm.startPrank(ADMIN);
        manager.setManageRoot(ADMIN, _getRoot());
        console.log("ROOT:");
        console.logBytes32(_getRoot());
        assertEq(manager.manageRoot(ADMIN), _getRoot(), "Root not set correctly");

        //=======================================================================================================================
        step1(myLeafs);
        step2(myLeafs);
        step3(myLeafs);
        step4(myLeafs);

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

        // _logManageVaultWithMerkleVerification(manager, manageProofs, decodersAndSanitizers, targets, targetData,
        // values);

        // manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
        // assertGe(ERC20(APX_ETH).balanceOf(address(boringVault)), TARGET_APX_ETH, "APX_ETH balance is less than
        // target");
        vm.stopPrank();

        // assertGe(pxETHValueOfAssets, wethBal, "Should get back more APX_ETH than WETH");
    }

    function step1(Leaf[] memory myLeafs) internal {
        uint256 SIZE = 3;
        bytes32[][] memory manageProofs = new bytes32[][](SIZE);
        address[] memory decodersAndSanitizers = new address[](SIZE);
        address[] memory targets = new address[](SIZE);
        bytes[] memory targetData = new bytes[](SIZE);
        uint256[] memory values = new uint256[](SIZE);
        uint256 i;

        // 0 Calldata
        decodersAndSanitizers[i] = myLeafs[0].decoderAndSanitizer;
        targets[i] = myLeafs[i].target;
        targetData[i] = abi.encodeWithSelector(myLeafs[0].selector);
        values[i] = _0_WETH;

        ++i;

        // 1 Calldata
        decodersAndSanitizers[i] = myLeafs[1].decoderAndSanitizer;
        targets[i] = myLeafs[1].target;
        targetData[i] = abi.encodeWithSelector(myLeafs[1].selector, CURVE_pufETH_wstETH, _1_pufETH);
        values[i] = 0;

        ++i;

        // 2 Calldata
        int128 _i = 0; // index of coin to send      [pufETH]
        int128 _j = 1; // index of coin to receive   [wstETH]
        decodersAndSanitizers[i] = myLeafs[2].decoderAndSanitizer;
        targets[i] = myLeafs[2].target;
        targetData[i] =
            abi.encodeWithSelector(myLeafs[2].selector, _i, _j, _2_pufETH, ACCEPTED_CURVE_RECEIVE_pufETH_4_wstETH);
        values[i] = 0;

        Leaf[] memory onlyMyLeafs = new Leaf[](SIZE);
        onlyMyLeafs[0] = myLeafs[0];
        onlyMyLeafs[1] = myLeafs[1];
        onlyMyLeafs[2] = myLeafs[2];

        manageProofs = _getProofsUsingTree(onlyMyLeafs, tree);

        console.log("===============STEP 1===============");
        _logManageVaultWithMerkleVerification(manager, manageProofs, decodersAndSanitizers, targets, targetData, values);
        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
    }

    function step2(Leaf[] memory myLeafs) internal {
        uint256 SIZE = 3;
        bytes32[][] memory manageProofs = new bytes32[][](SIZE);
        address[] memory decodersAndSanitizers = new address[](SIZE);
        address[] memory targets = new address[](SIZE);
        bytes[] memory targetData = new bytes[](SIZE);
        uint256[] memory values = new uint256[](SIZE);
        uint256 i;

        // 3 Calldata
        decodersAndSanitizers[i] = myLeafs[3].decoderAndSanitizer;
        targets[i] = myLeafs[3].target;
        targetData[i] = abi.encodeWithSelector(myLeafs[3].selector, _3_wstETH);
        values[i] = 0;

        ++i;

        // 4 Calldata
        decodersAndSanitizers[i] = myLeafs[4].decoderAndSanitizer;
        targets[i] = myLeafs[4].target;
        targetData[i] = abi.encodeWithSelector(myLeafs[4].selector, CURVE_pxETH_stETH, _4_stETH);
        values[i] = 0;

        ++i;

        // 5 Calldata
        int128 _i = 1; // index of coin to send      [stETH]
        int128 _j = 0; // index of coin to receive   [pxETH]
        decodersAndSanitizers[i] = myLeafs[5].decoderAndSanitizer;
        targets[i] = myLeafs[5].target;
        targetData[i] =
            abi.encodeWithSelector(myLeafs[5].selector, _i, _j, _5_stETH, ACCEPTED_CURVE_RECEIVE_pxETH_4_stETH);
        values[i] = 0;

        Leaf[] memory onlyMyLeafs = new Leaf[](SIZE);
        onlyMyLeafs[0] = myLeafs[3];
        onlyMyLeafs[1] = myLeafs[4];
        onlyMyLeafs[2] = myLeafs[5];

        manageProofs = _getProofsUsingTree(onlyMyLeafs, tree);
        console.log("===============STEP 2===============");
        _logManageVaultWithMerkleVerification(manager, manageProofs, decodersAndSanitizers, targets, targetData, values);
        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
    }

    function step3(Leaf[] memory myLeafs) internal {
        uint256 SIZE = 4;
        bytes32[][] memory manageProofs = new bytes32[][](SIZE);
        address[] memory decodersAndSanitizers = new address[](SIZE);
        address[] memory targets = new address[](SIZE);
        bytes[] memory targetData = new bytes[](SIZE);
        uint256[] memory values = new uint256[](SIZE);
        uint256 i;

        // 6 Calldata
        decodersAndSanitizers[i] = myLeafs[6].decoderAndSanitizer;
        targets[i] = myLeafs[6].target;
        targetData[i] = abi.encodeWithSelector(myLeafs[6].selector, CURVE_pxETH_WETH, _6_WETH);
        values[i] = 0;

        ++i;

        // 7 Calldata
        int128 _i = 0; // index of coin to send      [WETH]
        int128 _j = 1; // index of coin to receive   [pxETH]
        decodersAndSanitizers[i] = myLeafs[7].decoderAndSanitizer;
        targets[i] = myLeafs[7].target;
        targetData[i] =
            abi.encodeWithSelector(myLeafs[7].selector, _i, _j, _7_WETH, ACCEPTED_CURVE_RECEIVE_pxETH_4_WETH);
        values[i] = 0;

        ++i;

        // 8 Calldata
        decodersAndSanitizers[i] = myLeafs[8].decoderAndSanitizer;
        targets[i] = myLeafs[8].target;
        targetData[i] = abi.encodeWithSelector(myLeafs[8].selector, APX_ETH, _8_pxETH);
        values[i] = 0;

        ++i;

        // 9 Calldata
        decodersAndSanitizers[i] = myLeafs[9].decoderAndSanitizer;
        targets[i] = myLeafs[9].target;
        targetData[i] = abi.encodeWithSelector(myLeafs[9].selector, _9_pxETH, address(boringVault));
        values[i] = 0;

        Leaf[] memory onlyMyLeafs = new Leaf[](SIZE);
        onlyMyLeafs[0] = myLeafs[6];
        onlyMyLeafs[1] = myLeafs[7];
        onlyMyLeafs[2] = myLeafs[8];
        onlyMyLeafs[3] = myLeafs[9];

        manageProofs = _getProofsUsingTree(onlyMyLeafs, tree);

        console.log("===============STEP 3===============");
        _logManageVaultWithMerkleVerification(manager, manageProofs, decodersAndSanitizers, targets, targetData, values);
        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
    }

    function step4(Leaf[] memory myLeafs) internal {
        uint256 SIZE = 4;
        bytes32[][] memory manageProofs = new bytes32[][](SIZE);
        address[] memory decodersAndSanitizers = new address[](SIZE);
        address[] memory targets = new address[](SIZE);
        bytes[] memory targetData = new bytes[](SIZE);
        uint256[] memory values = new uint256[](SIZE);
        uint256 i;

        // 10 Calldata
        decodersAndSanitizers[i] = myLeafs[10].decoderAndSanitizer;
        targets[i] = myLeafs[10].target;
        targetData[i] = abi.encodeWithSelector(myLeafs[10].selector, CURVE_frxETH_WETH, _10_WETH);
        values[i] = 0;

        ++i;

        // 11 Calldata
        int128 _i = 0; // index of coin to send      [WETH]
        int128 _j = 1; // index of coin to receive   [frxETH]
        decodersAndSanitizers[i] = myLeafs[11].decoderAndSanitizer;
        targets[i] = myLeafs[11].target;
        targetData[i] =
            abi.encodeWithSelector(myLeafs[11].selector, _i, _j, _11_WETH, ACCEPTED_CURVE_RECEIVE_frxETH_4_WETH);
        values[i] = 0;

        ++i;

        // 12 Calldata
        decodersAndSanitizers[i] = myLeafs[12].decoderAndSanitizer;
        targets[i] = myLeafs[12].target;
        targetData[i] = abi.encodeWithSelector(myLeafs[12].selector, sfrxETH, _12_frxETH);
        values[i] = 0;

        ++i;

        // 13 Calldata
        decodersAndSanitizers[i] = myLeafs[13].decoderAndSanitizer;
        targets[i] = myLeafs[13].target;
        targetData[i] = abi.encodeWithSelector(myLeafs[13].selector, _13_frxETH, address(boringVault));
        values[i] = 0;

        Leaf[] memory onlyMyLeafs = new Leaf[](SIZE);
        onlyMyLeafs[0] = myLeafs[10];
        onlyMyLeafs[1] = myLeafs[11];
        onlyMyLeafs[2] = myLeafs[12];
        onlyMyLeafs[3] = myLeafs[13];

        manageProofs = _getProofsUsingTree(onlyMyLeafs, tree);

        console.log("===============STEP 4===============");
        // _logManageVaultWithMerkleVerification(manager, manageProofs, decodersAndSanitizers, targets, targetData,
        // values);
        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
    }

    function _setUpManager(uint256 depositAmount) internal { }

    function setUpDecoderSanitizers() public override {
        decoder = new SeiyanEthRebalanceDecoderAndSanitizer(address(boringVault));
    }
}
