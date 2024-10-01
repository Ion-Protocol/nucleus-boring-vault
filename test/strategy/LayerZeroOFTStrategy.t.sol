pragma solidity 0.8.21;

import { StrategyBase, Leaf } from "./StrategyBase.t.sol";
import {
    LayerZeroOFTDecoderAndSanitizer,
    BaseDecoderAndSanitizer
} from "src/base/DecodersAndSanitizers/LayerZeroOFTDecoderAndSanitizer.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { IStargate } from "@stargatefinance/stg-evm-v2/src/interfaces/IStargate.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { MessagingFee, OFTReceipt, SendParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { console } from "@forge-std/Test.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

address constant ADMIN = 0xF2dE1311C5b2C1BD94de996DA13F80010453e505;
address constant WETH = 0x160345fC359604fC6e70E3c5fAcbdE5F7A9342d8;
address constant STARGATE = 0x5c386D85b1B82FD9Db681b9176C8a4248bb6345B;
uint32 constant ETH_EID = 30_101;
uint256 constant SEI_TO_MINT = 100 ether;

contract LayerZeroOFTStrategy is StrategyBase {
    using OptionsBuilder for bytes;

    LayerZeroOFTDecoderAndSanitizer sanitizer;

    ManagerWithMerkleVerification manager = ManagerWithMerkleVerification(0x9B99d4584a3858C639F94fE055DB9E94017fE009);
    BoringVault boringVault = BoringVault(payable(0x9fAaEA2CDd810b21594E54309DC847842Ae301Ce));

    function setUp() public override {
        uint256 forkId = vm.createFork(vm.envString("L2_RPC_URL"));
        vm.selectFork(forkId);
        super.setUp();
    }

    function setUpDecoderSanitizers() public override {
        sanitizer = new LayerZeroOFTDecoderAndSanitizer(address(boringVault));
    }

    function testSend() external {
        deal(address(boringVault), SEI_TO_MINT);
        uint256 amountToSend = ERC20(WETH).balanceOf(address(boringVault));
        console.log(amountToSend);
        // owner prank
        // deploy sanitizer and build tree
        vm.startPrank(ADMIN);
        bytes memory packedArguments = abi.encodePacked(STARGATE);
        Leaf memory approveLeaf =
            Leaf(address(sanitizer), WETH, false, BaseDecoderAndSanitizer.approve.selector, packedArguments);
        packedArguments = abi.encodePacked(ETH_EID, addressToBytes32(address(boringVault)), ADMIN);
        Leaf memory sendLeaf =
            Leaf(address(sanitizer), STARGATE, true, LayerZeroOFTDecoderAndSanitizer.send.selector, packedArguments);

        Leaf[] memory myLeafs = new Leaf[](2);
        myLeafs[0] = approveLeaf;
        myLeafs[1] = sendLeaf;
        buildExampleTree(myLeafs);

        // set leaf in manager
        ManagerWithMerkleVerification manager = ManagerWithMerkleVerification(manager);
        manager.setManageRoot(ADMIN, _getRoot());
        vm.stopPrank();

        // strategist manages vault
        // in this case strategist is also admin
        vm.startPrank(ADMIN);
        bytes32[][] memory manageProofs = new bytes32[][](2);
        manageProofs[0] = _generateProof(_hashLeaf(approveLeaf), tree);
        manageProofs[1] = _generateProof(_hashLeaf(sendLeaf), tree);

        address[] memory decodersAndSanitizers = new address[](2);
        decodersAndSanitizers[0] = address(sanitizer);
        decodersAndSanitizers[1] = address(sanitizer);

        address[] memory targets = new address[](2);
        targets[0] = WETH;
        targets[1] = STARGATE;

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSelector(BaseDecoderAndSanitizer.approve.selector, STARGATE, amountToSend);

        bytes memory _extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(80_000, 0);
        SendParam memory sp = SendParam(
            ETH_EID, addressToBytes32(address(boringVault)), amountToSend, amountToSend, _extraOptions, "", new bytes(0)
        );

        (,, OFTReceipt memory receipt) = IStargate(STARGATE).quoteOFT(sp);
        sp.minAmountLD = receipt.amountReceivedLD;

        MessagingFee memory mf = IStargate(STARGATE).quoteSend(sp, false);
        uint256 valueToSend = mf.nativeFee;

        targetData[1] = abi.encodeWithSelector(LayerZeroOFTDecoderAndSanitizer.send.selector, sp, mf, ADMIN);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = valueToSend;

        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
        console.log("MinAmountLD: ", sp.minAmountLD);
        console.log("AmountLD: ", sp.amountLD);
        console.log("SEI Spent: ", SEI_TO_MINT - address(boringVault).balance);
        console.log("Value to Send: ", valueToSend);
        assertEq(ERC20(WETH).balanceOf(address(boringVault)), 0, "Boring Vault should have no more WETH");
    }

    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
