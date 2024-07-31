// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {MultiChainLayerZeroTellerWithMultiAssetSupport, BridgeData, ERC20, TellerWithMultiAssetSupport,MultiChainLayerZeroTellerWithMultiAssetSupportTest} from "../MultiChainLayerZeroTellerWithMultiAssetSupport.t.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

/**
 * @notice LayerZero normally is tested with a foundry testing framework that includes mocks for the crosschain ability,
 * Testing this live is not an option so most functions must be overriden and simplified to test only on the local chain
 */
contract LIVEMultiChainLayerZeroTellerWithMultiAssetSupportTest is MultiChainLayerZeroTellerWithMultiAssetSupportTest{
    using FixedPointMathLib for uint;

    address constant SOURCE_TELLER = 0xfFEa4FB47AC7FA102648770304605920CE35660c;
    address constant DESTINATION_TELLER = 0xfFEa4FB47AC7FA102648770304605920CE35660c;

    string constant RPC_KEY = "SEPOLIA_RPC_URL";

    function setUp() public virtual override {
        uint forkId = vm.createFork(vm.envString(RPC_KEY));
        vm.selectFork(forkId);
        address from = vm.envOr({name: "ETH_FROM", defaultValue: address(0)});
        vm.startPrank(from);


        sourceTellerAddr = SOURCE_TELLER;
        destinationTellerAddr = DESTINATION_TELLER;
        boringVault = MultiChainLayerZeroTellerWithMultiAssetSupport(sourceTellerAddr).vault();

        // deal(address(WETH), address(boringVault), 1_000e18);
        deal(address(boringVault), from, 1_000e18, true);
    }

    // function adjusted to only have source chain calls
    function testBridgingShares(uint256 sharesToBridge) external virtual override {
        MultiChainLayerZeroTellerWithMultiAssetSupport sourceTeller = MultiChainLayerZeroTellerWithMultiAssetSupport(sourceTellerAddr);

        sharesToBridge = uint96(bound(sharesToBridge, 1, 1_000e18));
        uint256 startingShareBalance = boringVault.balanceOf(address(this));
        // Setup chains on bridge.
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, destinationTellerAddr, CHAIN_MESSAGE_GAS_LIMIT, 0);

        // Bridge shares.
        address to = vm.addr(1);

        BridgeData memory data = BridgeData({
            chainSelector: DESTINATION_SELECTOR,
            destinationChainReceiver: to,
            bridgeFeeToken: ERC20(NATIVE),
            messageGas: 80_000,
            data: ""
        });

        uint quote = sourceTeller.previewFee(sharesToBridge, data);
        bytes32 id = sourceTeller.bridge{value:quote}(sharesToBridge, data);

        assertEq(
            boringVault.balanceOf(address(this)), startingShareBalance - sharesToBridge, "Should have burned shares."
        );

    }

    // function adjusted to only have source chain calls
    function testDepositAndBridgeFailsWithShareLockTime(uint amount) external virtual override{
        MultiChainLayerZeroTellerWithMultiAssetSupport sourceTeller = MultiChainLayerZeroTellerWithMultiAssetSupport(sourceTellerAddr);

        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, destinationTellerAddr, CHAIN_MESSAGE_GAS_LIMIT, 0);
        sourceTeller.setShareLockPeriod(60);

        amount = bound(amount, 0.0001e18, 10_000e18);
        // make a user and give them WETH
        address user = makeAddr("A user");
        address userChain2 = makeAddr("A user on chain 2");
        deal(address(WETH), user, amount);

        // approve teller to spend WETH
        vm.startPrank(user);
        vm.deal(user, 10e18);
        WETH.approve(address(boringVault), amount);

        // preform depositAndBridge
        BridgeData memory data = BridgeData({
            chainSelector: DESTINATION_SELECTOR,
            destinationChainReceiver: userChain2,
            bridgeFeeToken: ERC20(NATIVE),
            messageGas: 80_000,
            data: ""
        });

        uint ONE_SHARE = 10 ** boringVault.decimals();

        // so you don't really need to know exact shares in reality
        // just need to pass in a number roughly the same size to get quote
        // I still get the real number here for testing
        uint shares = amount.mulDivDown(ONE_SHARE, accountant.getRateInQuoteSafe(WETH));
        uint quote = sourceTeller.previewFee(shares, data);

        vm.expectRevert(bytes(abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__SharesAreLocked.selector)));
        sourceTeller.depositAndBridge{value:quote}(WETH, amount, shares, data);
    }

    // function adjusted to only have source chain calls
    function testDepositAndBridge(uint256 amount) external virtual override{
        MultiChainLayerZeroTellerWithMultiAssetSupport sourceTeller = MultiChainLayerZeroTellerWithMultiAssetSupport(sourceTellerAddr);

        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, destinationTellerAddr, CHAIN_MESSAGE_GAS_LIMIT, 0);
        
        amount = bound(amount, 0.0001e18, 10_000e18);
        // make a user and give them WETH
        address user = makeAddr("A user");
        address userChain2 = makeAddr("A user on chain 2");
        deal(address(WETH), user, amount);

        // approve teller to spend WETH
        vm.startPrank(user);
        vm.deal(user, 10e18);
        WETH.approve(address(boringVault), amount);

        // preform depositAndBridge
        BridgeData memory data = BridgeData({
            chainSelector: DESTINATION_SELECTOR,
            destinationChainReceiver: userChain2,
            bridgeFeeToken: ERC20(NATIVE),
            messageGas: 80_000,
            data: ""
        });

        uint ONE_SHARE = 10 ** boringVault.decimals();

        // so you don't really need to know exact shares in reality
        // just need to pass in a number roughly the same size to get quote
        // I still get the real number here for testing
        uint shares = amount.mulDivDown(ONE_SHARE, accountant.getRateInQuoteSafe(WETH));
        uint quote = sourceTeller.previewFee(shares, data);
        sourceTeller.depositAndBridge{value:quote}(WETH, amount, shares, data);

        assertEq(
            boringVault.balanceOf(user), 0, "Should have burned shares."
        );

        vm.stopPrank();
    }


    function testReverts() public virtual override{
        MultiChainLayerZeroTellerWithMultiAssetSupport sourceTeller = MultiChainLayerZeroTellerWithMultiAssetSupport(sourceTellerAddr);

        super.testReverts();

        // if the token is not NATIVE, should revert
        address NOT_NATIVE = 0xfAbA6f8e4a5E8Ab82F62fe7C39859FA577269BE3;
        BridgeData memory data = BridgeData(DESTINATION_SELECTOR, address(this), ERC20(NOT_NATIVE), 80_000, abi.encode(DESTINATION_SELECTOR));
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, destinationTellerAddr, CHAIN_MESSAGE_GAS_LIMIT, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                MultiChainLayerZeroTellerWithMultiAssetSupport.
                    MultiChainLayerZeroTellerWithMultiAssetSupport_InvalidToken.selector
            )
        );
        sourceTeller.bridge(1e18, data);

        // Call now succeeds.
        data = BridgeData(DESTINATION_SELECTOR, address(this), ERC20(NATIVE), 80_000, abi.encode(DESTINATION_SELECTOR));
        uint quote = sourceTeller.previewFee(1e18, data);

        sourceTeller.bridge{value:quote}(1e18, data);

    }

}