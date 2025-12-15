// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { WithdrawQueue } from "src/base/Roles/WithdrawQueue.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { SimpleFeeModule } from "src/helper/one-to-one-queue/SimpleFeeModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract tERC20 is ERC20 {

    constructor(uint8 _decimalsInput) ERC20("test name", "test", _decimalsInput) { }

}

contract BaseWithdrawQueueTest is Test {

    BoringVault boringVault;
    TellerWithMultiAssetSupport teller;
    AccountantWithRateProviders accountant;

    WithdrawQueue withdrawQueue;
    RolesAuthority rolesAuthority;

    IERC20 public USDC;

    address owner = makeAddr("owner");
    address user = makeAddr("user");
    address payout_address = makeAddr("payout_address");
    address feeRecipient = makeAddr("fee recipient");

    uint8 public constant MINTER_ROLE = 1;
    uint8 public constant BURNER_ROLE = 2;
    uint8 public constant QUEUE_ROLE = 8;
    uint256 public constant TEST_OFFER_FEE_PERCENTAGE = 10; // 0.1% fee

    // A simple params struct used in most tests
    WithdrawQueue.SignatureParams defaultParams = WithdrawQueue.SignatureParams({
        approvalMethod: WithdrawQueue.ApprovalMethod.EIP20_APROVE,
        approvalV: 0,
        approvalR: bytes32(0),
        approvalS: bytes32(0),
        submitWithSignature: false,
        deadline: block.timestamp + 1000,
        eip2612Signature: "",
        nonce: 0
    });

    function setUp() external virtual {
        vm.startPrank(owner);
        USDC = IERC20(address(new tERC20(6)));
        require(address(USDC) != address(0), "USDC is not deployed");

        // Deploy the vault contracts
        boringVault = new BoringVault(owner, "Boring Vault", "BV", 6);

        accountant = new AccountantWithRateProviders(
            owner, address(boringVault), payout_address, 1e6, address(USDC), 1.001e4, 0.999e4, 1, 0
        );

        teller = new TellerWithMultiAssetSupport(owner, address(boringVault), address(accountant));

        rolesAuthority = new RolesAuthority(owner, Authority(address(0)));

        SimpleFeeModule feeModule = new SimpleFeeModule(TEST_OFFER_FEE_PERCENTAGE);
        withdrawQueue = new WithdrawQueue("Withdraw Queue", "WQ", feeRecipient, teller, feeModule, owner);

        // Set Role Authorities, user roles and Capabilities
        boringVault.setAuthority(rolesAuthority);
        accountant.setAuthority(rolesAuthority);
        teller.setAuthority(rolesAuthority);
        withdrawQueue.setAuthority(rolesAuthority);

        rolesAuthority.setRoleCapability(MINTER_ROLE, address(boringVault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(boringVault), BoringVault.exit.selector, true);
        rolesAuthority.setRoleCapability(
            QUEUE_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );

        rolesAuthority.setPublicCapability(address(teller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(
            address(teller), TellerWithMultiAssetSupport.depositWithPermit.selector, true
        );
        rolesAuthority.setPublicCapability(address(withdrawQueue), WithdrawQueue.submitOrder.selector, true);
        rolesAuthority.setPublicCapability(address(withdrawQueue), WithdrawQueue.processOrders.selector, true);
        rolesAuthority.setPublicCapability(address(withdrawQueue), WithdrawQueue.submitOrderAndProcess.selector, true);
        rolesAuthority.setPublicCapability(
            address(withdrawQueue), WithdrawQueue.submitOrderAndProcessAll.selector, true
        );

        rolesAuthority.setUserRole(address(withdrawQueue), QUEUE_ROLE, true);
        rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);

        teller.addAsset(ERC20(address(USDC)));
        vm.stopPrank();
    }

    function _getFees(uint256 amount) internal view returns (uint256) {
        return amount * TEST_OFFER_FEE_PERCENTAGE / 10_000;
    }

    function _getAmountAfterFees(uint256 amount) internal view returns (uint256) {
        return amount - _getFees(amount);
    }

}
