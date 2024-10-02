pragma solidity 0.8.21;

import { StrategyBase, Leaf } from "./StrategyBase.t.sol";
import { NativeWrapperDecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/NativeWrapperDecoderAndSanitizer.sol";
import {
    SeiyanEthRebalanceDecoderAndSanitizer,
    BaseDecoderAndSanitizer,
    NativeWrapperDecoderAndSanitizer,
    ERC4626DecoderAndSanitizer,
    CurveDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/SeiyanEthRebalanceDecoderAndSanitizer.sol";

import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { console } from "@forge-std/Test.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

address constant ADMIN = 0x0000000000417626Ef34D62C4DC189b021603f2F;
address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant APX_ETH = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;
address constant PX_ETH = 0x04C154b66CB340F3Ae24111CC767e0184Ed00Cc6;
address constant PIREX_ETH = 0xD664b74274DfEB538d9baC494F3a4760828B02b0;
address constant CURVE = 0xC8Eb2Cf2f792F77AF0Cd9e203305a585E588179D;
uint256 constant SEI_WETH = 93.5214859e18;
uint256 constant TARGET_APX_ETH = 235.2211814e18;
uint256 constant ACCEPTED_CURVE_RECEIVE = 10e18;

contract SeiyanEthRebalanceStrategyTest is StrategyBase {
    using Address for address;

    ERC20 base = ERC20(WETH);
    ManagerWithMerkleVerification manager = ManagerWithMerkleVerification(0x9B99d4584a3858C639F94fE055DB9E94017fE009);
    BoringVault boringVault = BoringVault(payable(0x9fAaEA2CDd810b21594E54309DC847842Ae301Ce));
    SeiyanEthRebalanceDecoderAndSanitizer decoder;

    function setUp() public override {
        uint256 forkId = vm.createFork(vm.envString("L1_RPC_URL"));
        vm.selectFork(forkId);
        super.setUp();
    }

    function setUpDecoderSanitizers() public override {
        decoder = new SeiyanEthRebalanceDecoderAndSanitizer(address(boringVault));
    }

    function testRebalance() public {
        uint256 vaultBalance = base.balanceOf(address(boringVault));

        // deal the eth we are expecting to receive
        deal(address(boringVault), vaultBalance + SEI_WETH);

        vaultBalance = address(boringVault).balance;

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

        // leaf 1 = approve Curve Router to spend all WETH
        uint256 wethBal = ERC20(WETH).balanceOf(address(boringVault));
        packedArguments = abi.encodePacked(CURVE);
        myLeafs[1] = Leaf(address(decoder), WETH, false, BaseDecoderAndSanitizer.approve.selector, packedArguments);
        // leaf 1 Calldata
        decodersAndSanitizers[1] = myLeafs[1].decoderAndSanitizer;
        targets[1] = myLeafs[1].target;
        targetData[1] = abi.encodeWithSelector(myLeafs[1].selector, CURVE, wethBal);
        values[1] = 0;

        // leaf 2 = call Curve exchange
        int128 i = 0; // index of coin to send
        int128 j = 1; // index of coin to receive
        packedArguments = "";
        myLeafs[2] = Leaf(address(decoder), CURVE, false, CurveDecoderAndSanitizer.exchange.selector, packedArguments);
        // leaf 2 Calldata
        decodersAndSanitizers[2] = myLeafs[2].decoderAndSanitizer;
        targets[2] = myLeafs[2].target;
        targetData[2] = abi.encodeWithSelector(myLeafs[2].selector, i, j, wethBal, ACCEPTED_CURVE_RECEIVE);
        values[2] = 0;

        // leaf 3 = approve apxETH to spend all pxETH
        packedArguments = abi.encodePacked(APX_ETH);
        myLeafs[3] = Leaf(address(decoder), PX_ETH, false, BaseDecoderAndSanitizer.approve.selector, packedArguments);
        // leaf 3 Calldata
        decodersAndSanitizers[3] = myLeafs[3].decoderAndSanitizer;
        targets[3] = myLeafs[3].target;
        targetData[3] = abi.encodeWithSelector(myLeafs[3].selector, APX_ETH, ACCEPTED_CURVE_RECEIVE);
        values[3] = 0;

        // leaf 4 = ERC4626 deposit on apxETH with pxETH
        packedArguments = abi.encodePacked(address(boringVault));
        myLeafs[4] =
            Leaf(address(decoder), APX_ETH, false, ERC4626DecoderAndSanitizer.deposit.selector, packedArguments);
        // leaf 4 Calldata
        decodersAndSanitizers[4] = myLeafs[4].decoderAndSanitizer;
        targets[4] = myLeafs[4].target;
        targetData[4] = abi.encodeWithSelector(myLeafs[4].selector, ACCEPTED_CURVE_RECEIVE, address(boringVault));
        values[4] = 0;

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

        _logManageVaultWithMerkleVerification(manager, manageProofs, decodersAndSanitizers, targets, targetData, values);

        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
        assertGe(ERC20(APX_ETH).balanceOf(address(boringVault)), TARGET_APX_ETH, "APX_ETH balance is less than target");
        vm.stopPrank();
    }

    function _setUpManager(uint256 depositAmount) internal { }
}
