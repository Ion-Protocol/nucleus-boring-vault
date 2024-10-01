pragma solidity 0.8.21;

import { StrategyBase, Leaf } from "./StrategyBase.t.sol";
import { SeiyanEthRebalanceDecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/SeiyanEthRebalanceDecoderAndSanitizer.sol";
import { NativeWrapperDecoderAndSanitizer } from
    "src/base/DecodersAndSanitizers/Protocols/NativeWrapperDecoderAndSanitizer.sol";
import { PirexEthDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/Protocols/PirexEthDecoderAndSanitizer.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { console } from "@forge-std/Test.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

address constant ADMIN = 0x0000000000417626Ef34D62C4DC189b021603f2F;
address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant APX_ETH = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;
address constant PIREX_ETH = 0xD664b74274DfEB538d9baC494F3a4760828B02b0;
uint256 constant SEI_WETH = 93.5214859e18;
uint256 constant TARGET_APX_ETH = 235.2211814e18;

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
        // to-do DEAL new WETH that would be bridged
        uint256 vaultBalance = base.balanceOf(address(boringVault));
        deal(WETH, address(boringVault), vaultBalance + SEI_WETH);
        vaultBalance = base.balanceOf(address(boringVault));
        _setUpManager(vaultBalance);
        assertEq(manager.manageRoot(ADMIN), _getRoot(), "Root not set correctly");

        Leaf[] memory myLeafs = _getLeafsForTest(vaultBalance);

        bytes32[][] memory manageProofs = new bytes32[][](2);
        address[] memory decodersAndSanitizers = new address[](2);
        address[] memory targets = new address[](2);
        bytes[] memory targetData = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        manageProofs = _getProofsUsingTree(myLeafs, tree);
        decodersAndSanitizers[0] = myLeafs[0].decoderAndSanitizer;
        decodersAndSanitizers[1] = myLeafs[1].decoderAndSanitizer;

        targets[0] = myLeafs[0].target;
        targets[1] = myLeafs[1].target;

        targetData[0] = abi.encodeWithSelector(myLeafs[0].selector, vaultBalance);
        targetData[1] = abi.encodeWithSelector(myLeafs[1].selector, address(boringVault), true);

        values[0] = 0;
        values[1] = vaultBalance;

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
        vm.prank(ADMIN);
        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
        assertGe(ERC20(APX_ETH).balanceOf(address(boringVault)), TARGET_APX_ETH, "APX_ETH balance is less than target");
    }

    function _setUpManager(uint256 depositAmount) internal {
        vm.startPrank(ADMIN);
        // admin allows strategy for deposit to APX ETH returning tokens to boring vault
        Leaf[] memory myLeafs = _getLeafsForTest(depositAmount);
        buildExampleTree(myLeafs);
        bytes32 root = _getRoot();

        manager.setManageRoot(ADMIN, root);
        vm.stopPrank();
    }

    function _getLeafsForTest(uint256 depositAmount) internal returns (Leaf[] memory myLeafs) {
        // weth -> eth
        Leaf memory wethForEthLeaf =
            Leaf(address(decoder), WETH, false, NativeWrapperDecoderAndSanitizer.withdraw.selector, "");

        // eth -> pirexETH for apxETH
        bytes memory packedArguments = abi.encodePacked(address(boringVault));
        Leaf memory pirexEthLeaf =
            Leaf(address(decoder), PIREX_ETH, true, PirexEthDecoderAndSanitizer.deposit.selector, packedArguments);
        myLeafs = new Leaf[](2);

        myLeafs[0] = wethForEthLeaf;
        myLeafs[1] = pirexEthLeaf;
    }
}
