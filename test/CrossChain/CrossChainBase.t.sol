// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {MainnetAddresses} from "test/resources/MainnetAddresses.sol";
import {BoringVault} from "src/base/BoringVault.sol";
import {AccountantWithRateProviders} from "src/base/Roles/AccountantWithRateProviders.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {TellerWithMultiAssetSupport} from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import {CrossChainTellerBase, BridgeData} from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";

import "src/interfaces/ICrossChainTeller.sol";

import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";

abstract contract CrossChainBaseTest is Test, MainnetAddresses {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;

    BoringVault public boringVault;

    uint8 public constant ADMIN_ROLE = 1;
    uint8 public constant MINTER_ROLE = 7;
    uint8 public constant BURNER_ROLE = 8;
    uint8 public constant SOLVER_ROLE = 9;
    uint8 public constant QUEUE_ROLE = 10;
    uint8 public constant CAN_SOLVE_ROLE = 11;

    uint64 constant CHAIN_MESSAGE_GAS_LIMIT = 100_000;

    AccountantWithRateProviders public accountant;
    address public payout_address = vm.addr(7777777);
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ERC20 internal constant NATIVE_ERC20 = ERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    RolesAuthority public rolesAuthority;

    uint32 public constant SOURCE_SELECTOR = 1;
    uint32 public constant DESTINATION_SELECTOR = 2;

    CrossChainTellerBase sourceTeller;
    CrossChainTellerBase destinationTeller;

    function _deploySourceAndDestinationTeller() internal virtual{
    }

    function setUp() public virtual{
        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19363419;
        _startFork(rpcKey, blockNumber);

        boringVault = new BoringVault(address(this), "Boring Vault", "BV", 18);

        accountant = new AccountantWithRateProviders(
            address(this), address(boringVault), payout_address, 1e18, address(WETH), 1.001e4, 0.999e4, 1, 0
        );

        _deploySourceAndDestinationTeller();

        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));

        boringVault.setAuthority(rolesAuthority);
        accountant.setAuthority(rolesAuthority);
        sourceTeller.setAuthority(rolesAuthority);
        destinationTeller.setAuthority(rolesAuthority);

        rolesAuthority.setRoleCapability(MINTER_ROLE, address(boringVault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(boringVault), BoringVault.exit.selector, true);

        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(sourceTeller), TellerWithMultiAssetSupport.addAsset.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(sourceTeller), TellerWithMultiAssetSupport.removeAsset.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(sourceTeller), TellerWithMultiAssetSupport.bulkDeposit.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(sourceTeller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(sourceTeller), TellerWithMultiAssetSupport.refundDeposit.selector, true
        );
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(sourceTeller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setPublicCapability(address(sourceTeller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(
            address(sourceTeller), TellerWithMultiAssetSupport.depositWithPermit.selector, true
        );
        rolesAuthority.setPublicCapability(address(destinationTeller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(
            address(destinationTeller), TellerWithMultiAssetSupport.depositWithPermit.selector, true
        );
        
        rolesAuthority.setPublicCapability(address(sourceTeller), CrossChainTellerBase.bridge.selector, true);
        rolesAuthority.setPublicCapability(address(destinationTeller), CrossChainTellerBase.bridge.selector, true);
        rolesAuthority.setPublicCapability(address(sourceTeller), CrossChainTellerBase.depositAndBridge.selector, true);
        rolesAuthority.setPublicCapability(address(destinationTeller), CrossChainTellerBase.depositAndBridge.selector, true);

        rolesAuthority.setUserRole(address(sourceTeller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(sourceTeller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(destinationTeller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(destinationTeller), BURNER_ROLE, true);

        sourceTeller.addAsset(WETH);
        sourceTeller.addAsset(ERC20(NATIVE));
        sourceTeller.addAsset(EETH);
        sourceTeller.addAsset(WEETH);

        destinationTeller.addAsset(WETH);
        destinationTeller.addAsset(ERC20(NATIVE));
        destinationTeller.addAsset(EETH);
        destinationTeller.addAsset(WEETH);

        accountant.setRateProviderData(EETH, true, address(0));
        accountant.setRateProviderData(WEETH, false, address(WEETH_RATE_PROVIDER));

        // Give BoringVault some WETH, and this address some shares, and LINK.
        deal(address(WETH), address(boringVault), 1_000e18);
        deal(address(boringVault), address(this), 1_000e18, true);
        deal(address(LINK), address(this), 1_000e18);
    }

    function testReverts() public virtual{
        // Adding a chain with a zero message gas limit should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainTellerBase_ZeroMessageGasLimit.selector))
        );
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 0, 0);        

        // Allowing messages to a chain with a zero message gas limit should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainTellerBase_ZeroMessageGasLimit.selector))
        );
        sourceTeller.allowMessagesToChain(DESTINATION_SELECTOR, address(destinationTeller), 0);

        // Changing the gas limit to zero should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(CrossChainTellerBase_ZeroMessageGasLimit.selector))
        );
        sourceTeller.setChainGasLimit(DESTINATION_SELECTOR, 0);

        // But you can add a chain with a non-zero message gas limit, if messages to are not supported.
        uint32 newChainSelector = 3;
        sourceTeller.addChain(newChainSelector, true, false, address(destinationTeller), 0, 0);

        // If teller is paused bridging is not allowed.
        sourceTeller.pause();
        vm.expectRevert(
            bytes(abi.encodeWithSelector(TellerWithMultiAssetSupport.TellerWithMultiAssetSupport__Paused.selector))
        );

        BridgeData memory data = BridgeData(DESTINATION_SELECTOR, address(0), ERC20(address(0)), 80_000, "");
        sourceTeller.bridge(0, data);

        sourceTeller.unpause();

        // Trying to send messages to a chain that is not supported should revert.
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    CrossChainTellerBase_MessagesNotAllowedTo.selector, DESTINATION_SELECTOR
                )
            )
        );

        data = BridgeData(DESTINATION_SELECTOR, address(this), ERC20(NATIVE), 80_000, abi.encode(DESTINATION_SELECTOR));
        sourceTeller.bridge(1e18, data);

        // setup chains.
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 100_000, 0);
        destinationTeller.addChain(SOURCE_SELECTOR, true, true, address(sourceTeller), 100_000, 0);

        // if too much gas is used, revert
        data = BridgeData(DESTINATION_SELECTOR, address(this), ERC20(NATIVE), CHAIN_MESSAGE_GAS_LIMIT+1, abi.encode(DESTINATION_SELECTOR));
        vm.expectRevert(
            abi.encodeWithSelector(
                    CrossChainTellerBase_GasLimitExceeded.selector
            )
        );
        sourceTeller.bridge(1e18, data);

        // if min gas is set too high, revert
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), CHAIN_MESSAGE_GAS_LIMIT, CHAIN_MESSAGE_GAS_LIMIT);
        data = BridgeData(DESTINATION_SELECTOR, address(this), ERC20(NATIVE), 80_000, abi.encode(DESTINATION_SELECTOR));
        vm.expectRevert(
            abi.encodeWithSelector(
                    CrossChainTellerBase_GasTooLow.selector
            )
        );
        sourceTeller.bridge(1e18, data);

    }


    // ========================================= HELPER FUNCTIONS =========================================

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }
}
