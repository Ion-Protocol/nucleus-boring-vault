pragma solidity 0.8.21;

import { StrategyBase, Leaf } from "./StrategyBase.t.sol";
import { LayerZeroOFTDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/LayerZeroOFTDecoderAndSanitizer.sol";

import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";

contract LayerZeroOFTStrategy is StrategyBase {
    uint256 constant ETH_EID = 30_101;

    LayerZeroOFTDecoderAndSanitizer sanitizer;

    function setUpDecoderSanitizers() public override {
        sanitizer = new LayerZeroOFTDecoderAndSanitizer(mainConfig.boringVault);
    }

    function testSend() external {
        // owner prank
        // deploy sanitizer and build tree
        vm.startPrank(mainConfig.protocolAdmin);
        bytes memory packedArguments = abi.encodePacked(ETH_EID, address(this));
        Leaf memory myLeaf = Leaf(
            address(sanitizer), mainConfig.base, false, LayerZeroOFTDecoderAndSanitizer.send.selector, packedArguments
        );
        buildExampleTree(myLeaf);

        // set leaf in manager
        ManagerWithMerkleVerification manager = ManagerWithMerkleVerification(mainConfig.manager);
        manager.setManageRoot(mainConfig.strategist, _getRoot());
        vm.stopPrank();

        // strategist manages vault
        vm.startPrank(mainConfig.strategist);
        bytes32[][] memory manageProofs = new bytes32[][](1);
        manageProofs[0] = _generateProof(_hashLeaf(myLeaf), tree);

        address[] memory decodersAndSanitizers = new address[](1);
        decodersAndSanitizers[0] = address(sanitizer);

        address[] memory targets = new address[](1);
        targets[0] = mainConfig.base;

        bytes[] memory targetData = new bytes[](1);
        targetData[0] = abi.encodeWithSelector(LayerZeroOFTDecoderAndSanitizer.send.selector, packedArguments);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        manager.manageVaultWithMerkleVerification(manageProofs, decodersAndSanitizers, targets, targetData, values);
    }
}
