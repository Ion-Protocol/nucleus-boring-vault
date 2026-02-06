// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test } from "@forge-std/Test.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { DistributorCodeDepositor } from "src/helper/DistributorCodeDepositor.sol";
import { WithdrawQueue } from "src/base/Roles/WithdrawQueue.sol";
import { SimpleFeeModule } from "src/helper/one-to-one-queue/SimpleFeeModule.sol";

import { IBoringVault } from "src/interfaces/IBoringVault.sol";
import { ITellerWithMultiAssetSupport } from "src/interfaces/Roles/ITellerWithMultiAssetSupport.sol";
import { IAccountantWithRateProviders } from "src/interfaces/Roles/IAccountantWithRateProviders.sol";

import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { RedEnvelopeUpgrade, CONTRACT } from "src/helper/upgrade/RedEnvelope.sol";
import { ICreateX } from "lib/createx/src/ICreateX.sol";

contract RedEnvelopeUpgradeTest is Test {

    // Existing deployed contracts on mainnet (earnUSDG)
    IBoringVault constant BORING_VAULT = IBoringVault(payable(0xcB25f8a0ee2850C11F8A2848e722f70Bd6bA5D9C));
    IAccountantWithRateProviders constant ACCOUNTANT1 =
        IAccountantWithRateProviders(0x99cCA5087479E092F63874E7Fb7356C143623B26);
    ITellerWithMultiAssetSupport constant TELLER1 =
        ITellerWithMultiAssetSupport(0x094c771B02094482C2D514ac46d793c8A9f5F693);
    RolesAuthority constant ROLES_AUTHORITY = RolesAuthority(0xaeeC053e978A4Bfc05BEBf297250cE8528B8530d);

    RedEnvelopeUpgrade upgradeContract;
    ICreateX createX;
    address multisig;
    address withdrawQueueProcessor = makeAddr("processor");
    address queueFeeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        // Fork Ethereum mainnet
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(forkId);

        // Get CreateX address from environment variable
        createX = ICreateX(vm.envAddress("CREATEX"));

        // Query the owner of the contracts to get the multisig address
        multisig = ACCOUNTANT1.owner();

        // Verify all contracts have the same owner
        assertEq(ROLES_AUTHORITY.owner(), multisig, "RolesAuthority owner mismatch");
        assertEq(ACCOUNTANT1.owner(), multisig, "Accountant1 owner mismatch");

        // Deploy RedEnvelope upgrade contract
        upgradeContract = new RedEnvelopeUpgrade(address(createX), multisig);
    }

    function testFlashUpgrade() public {
        // Transfer ownership of accountant and roles authority to upgrade contract
        vm.prank(multisig);
        ACCOUNTANT1.transferOwnership(address(upgradeContract));

        vm.prank(multisig);
        ROLES_AUTHORITY.transferOwnership(address(upgradeContract));

        // Verify ownership was transferred
        assertEq(ACCOUNTANT1.owner(), address(upgradeContract), "Accountant1 ownership not transferred");
        assertEq(ROLES_AUTHORITY.owner(), address(upgradeContract), "RolesAuthority ownership not transferred");

        bytes memory accountantCreationCode = type(AccountantWithRateProviders).creationCode;
        bytes memory tellerCreationCode = type(TellerWithMultiAssetSupport).creationCode;
        bytes memory dcdCreationCode = type(DistributorCodeDepositor).creationCode;
        bytes memory withdrawQueueCreationCode = type(WithdrawQueue).creationCode;
        bytes memory feeModuleCreationCode = type(SimpleFeeModule).creationCode;

        vm.startPrank(multisig);
        upgradeContract.setContractCreationCode(CONTRACT.ACCOUNTANT2, accountantCreationCode);
        upgradeContract.setContractCreationCode(CONTRACT.TELLER2, tellerCreationCode);
        upgradeContract.setContractCreationCode(CONTRACT.DCD2, dcdCreationCode);
        upgradeContract.setContractCreationCode(CONTRACT.WITHDRAW_QUEUE, withdrawQueueCreationCode);
        upgradeContract.setContractCreationCode(CONTRACT.FEE_MODULE, feeModuleCreationCode);
        vm.stopPrank();

        // Prepare upgrade parameters
        RedEnvelopeUpgrade.FlashUpgradeParams memory params = RedEnvelopeUpgrade.FlashUpgradeParams({
            accountant1: ACCOUNTANT1,
            teller1: TELLER1,
            authority: ROLES_AUTHORITY,
            accountantPerformanceFee: 100, // 1%
            offerFeePercentage: 2, // 0.02%
            depositAssets: new address[](0),
            withdrawAssets: new address[](0),
            withdrawQueueProcessorAddress: withdrawQueueProcessor,
            queueFeeRecipient: queueFeeRecipient,
            minimumOrderSize: 0,
            queueErc721Name: "Test Queue",
            queueErc721Symbol: "TQ"
        });

        // Execute upgrade as multisig
        vm.prank(multisig);
        RedEnvelopeUpgrade.DeployedContracts memory deployedContracts = upgradeContract.flashUpgrade(params);

        // Verify ownership was returned to multisig
        assertEq(ROLES_AUTHORITY.owner(), multisig, "RolesAuthority ownership not returned");
        assertEq(ACCOUNTANT1.owner(), multisig, "Accountant1 ownership not returned");

        assertEq(deployedContracts.accountant2.owner(), multisig, "Accountant2 ownership not returned");
        assertEq(deployedContracts.teller2.owner(), multisig, "Teller2 ownership not returned");
        assertEq(deployedContracts.withdrawQueue.owner(), multisig, "WithdrawQueue ownership not returned");

        // Verify new contracts were deployed
        assertTrue(address(deployedContracts.accountant2) != address(0), "Accountant2 not deployed");
        assertTrue(address(deployedContracts.teller2) != address(0), "Teller2 not deployed");
        assertTrue(address(deployedContracts.dcd2) != address(0), "DCD2 not deployed");
        assertTrue(address(deployedContracts.withdrawQueue) != address(0), "WithdrawQueue not deployed");
        assertTrue(address(deployedContracts.feeModule) != address(0), "FeeModule not deployed");
    }

}
