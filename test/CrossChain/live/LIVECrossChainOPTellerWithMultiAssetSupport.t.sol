// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {
    CrossChainOPTellerWithMultiAssetSupportTest,
    CrossChainOPTellerWithMultiAssetSupport
} from "../CrossChainOPTellerWithMultiAssetSupport.t.sol";

/**
 * @notice live test for OP Teller, since OP doesn't use any sort of mock handlers or testing contracts, it is able to
 * be almost entierly inherited from it's local test parent, with just adjusting the deployment with the existing
 * addresses.
 */
contract LIVECrossChainOPTTellerWithMultiAssetSupportTest is CrossChainOPTellerWithMultiAssetSupportTest {
    address constant SOURCE_TELLER = 0x8D9d36a33DAD6fb622180b549aB05B6ED71350F7;
    address constant DESTINATION_TELLER = 0x8D9d36a33DAD6fb622180b549aB05B6ED71350F7;
    string constant RPC_KEY = "SEPOLIA_RPC_URL";
    address from;

    function setUp() public virtual override {
        uint256 forkId = vm.createFork(vm.envString(RPC_KEY));
        vm.selectFork(forkId);
        from = vm.envOr({ name: "ETH_FROM", defaultValue: address(0) });
        vm.startPrank(from);

        sourceTellerAddr = SOURCE_TELLER;
        destinationTellerAddr = DESTINATION_TELLER;
        boringVault = CrossChainOPTellerWithMultiAssetSupport(sourceTellerAddr).vault();
        accountant = CrossChainOPTellerWithMultiAssetSupport(sourceTellerAddr).accountant();

        CrossChainOPTellerWithMultiAssetSupport(sourceTellerAddr).setGasBounds(0, uint32(CHAIN_MESSAGE_GAS_LIMIT));

        // deal(address(WETH), address(boringVault), 1_000e18);
        deal(address(boringVault), from, 1000e18, true);
        // deal(address(LINK), address(this), 1_000e18);
    }

    function testBridgingShares(uint256 sharesToBridge) public virtual override {
        vm.startPrank(from);
        super.testBridgingShares(sharesToBridge);
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal virtual override returns (uint256 forkId) { }

    function _deploySourceAndDestinationTeller() internal virtual override { }

    function testReverts() public virtual override {
        vm.startPrank(from);
        super.testReverts();
    }
}
