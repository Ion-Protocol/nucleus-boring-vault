// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { TellerWithMultiAssetSupport, ERC20 } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { DistributorCodeDepositor } from "src/helper/DistributorCodeDepositor.sol";
import { ICreateX } from "lib/createx/src/ICreateX.sol";
import { SimpleFeeModule } from "src/helper/one-to-one-queue/SimpleFeeModule.sol";
import { WithdrawQueue } from "src/base/Roles/WithdrawQueue.sol";
import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import "src/helper/constants.sol";

/**
 * @dev interface for the accountant we are replacing (Accountant1). All else being equal, we only use this to call
 * `accountantState()`
 */
interface IAccountant1 {

    function accountantState()
        external
        view
        returns (
            address payoutAddress,
            uint128 feesOwedInBase,
            uint128 totalSharesLastUpdate,
            uint96 exchangeRate,
            uint16 allowedExchangeRateChangeUpper,
            uint16 allowedExchangeRateChangeLower,
            uint64 lastUpdateTimestamp,
            bool isPaused,
            uint32 minimumUpdateDelayInSeconds,
            uint16 managementFee
        );

}

/**
 * @title RedEnvelopeUpgrade
 * @notice Red Envelope is the codename for a PaxosLabs Feb 2026 vault upgrade that includes the following:
 * - Upgrade the Teller contract to support withdraw and deposit asset distinctly
 * - The Teller also has bulkDeposit removed
 * - A new DistributorCodeDepositor is also created
 * - Upgrade the Accountant contract to support performance fees
 * - The new WithdrawQueue contract is deployed with a supporting Fee Module
 *
 * @dev This contract uses a "flash-upgrade" method to upgrade the vault with temporarily provided ownership.
 * @custom:security-contact security@molecularlabs.io
 */
contract RedEnvelopeUpgrade {

    struct FlashUpgradeParams {
        AccountantWithRateProviders accountant1;
        TellerWithMultiAssetSupport teller1;
        RolesAuthority authority;
        uint16 accountantPerformanceFee;
        uint256 offerFeePercentage;
        address[] depositAssets;
        address[] withdrawAssets;
        address withdrawQueueProcessorAddress;
        address queueFeeRecipient;
        uint256 minimumOrderSize;
        string queueErc721Name;
        string queueErc721Symbol;
    }

    // Constants and immutables
    ICreateX immutable CREATEX;
    address immutable multisig;

    // Deployed Contracts
    AccountantWithRateProviders public accountant2;
    TellerWithMultiAssetSupport public teller2;
    DistributorCodeDepositor public dcd2;
    WithdrawQueue public withdrawQueue;
    SimpleFeeModule public feeModule;

    event ContractDeployed(string name, address contractAddress);

    constructor(address _createx, address _multisig) {
        CREATEX = ICreateX(_createx);
        multisig = _multisig;
    }

    /**
     * @dev As an emergency measure, we allow the multisig to use this address to do anything. If a dangling ownership
     * is forgotten we can always recover it
     */
    function emergencyProxyCall(address _target, bytes memory _data, uint256 _value) external {
        require(msg.sender == multisig, "Only the multisig can call this function");

        _target.call{ value: _value }(_data);
    }

    /**
     * @notice flash upgrade function. Requires this contract is granted ownership of the accountant and roles authority
     */
    function flashUpgrade(FlashUpgradeParams calldata params) external {
        string memory symbol = params.teller1.vault().symbol();

        require(msg.sender == multisig, "Only the multisig can call this function");
        require(params.accountant1.owner() == address(this), "Accountant1 must be owned by this contract");
        require(params.authority.owner() == address(this), "Authority must be owned by this contract");

        // Freeze the exchange rate from changing on the old accountant
        params.accountant1.updateUpper(1e4);
        params.accountant1.updateLower(1e4);

        // Deploy the new Accountant
        // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        {
            // First fetch the configuration values from the accountant being replaced
            (
                address _payoutAddress,,,
                uint96 _exchangeRate,,,,,
                uint32 _minimumUpdateDelayInSeconds,
                uint16 _managementFee
            ) = IAccountant1(address(params.accountant1)).accountantState();

            // We set the constructor args = the old accountant with only the new performance fee being unique
            bytes memory constructorParams = abi.encode(
                address(this), // Owner is set to this flash-upgrade contract for now
                params.accountant1.vault(),
                _payoutAddress,
                _exchangeRate,
                params.accountant1.base(),
                1e4, // New Accountant is also frozen from rate changes
                1e4, // ^
                _minimumUpdateDelayInSeconds,
                _managementFee,
                params.accountantPerformanceFee
            );

            bytes memory initCode = abi.encodePacked(type(AccountantWithRateProviders).creationCode, constructorParams);

            // Deploy
            accountant2 = AccountantWithRateProviders(
                CREATEX.deployCreate3(_makeSalt(false, symbol, "AccountantRedEnvelope"), initCode)
            );
        }

        // Set the Authority of the new accountant
        accountant2.setAuthority(params.authority);

        // Set the Role Capabilities for the new accountant
        params.authority
            .setRoleCapability(
                UPDATE_EXCHANGE_RATE_ROLE,
                address(accountant2),
                AccountantWithRateProviders.updateExchangeRate.selector,
                true
            );
        params.authority
            .setRoleCapability(PAUSER_ROLE, address(accountant2), AccountantWithRateProviders.pause.selector, true);

        // Deploy the Teller
        // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        // NOTE: We set the owner to this flash-upgrade contract for now
        teller2 = TellerWithMultiAssetSupport(
            CREATEX.deployCreate3(
                _makeSalt(false, symbol, "TellerRedEnvelope"),
                abi.encodePacked(
                    type(TellerWithMultiAssetSupport).creationCode,
                    abi.encode(address(this), params.teller1.vault(), address(accountant2))
                )
            )
        );

        // Set the Authority of the new teller
        teller2.setAuthority(params.authority);

        // Add the base asset support (both for deposit and withdraw)
        teller2.addDepositAsset(params.accountant1.base());
        teller2.addWithdrawAsset(params.accountant1.base());

        // Set the Role Capabilities for the new teller
        // NOTE: IMPORTANT we set the rate provider as address(0) and pegged for all assets
        for (uint256 i; i < params.depositAssets.length; ++i) {
            teller2.addDepositAsset(ERC20(params.depositAssets[i]));
            accountant2.setRateProviderData(ERC20(params.depositAssets[i]), true, address(0));
        }

        // NOTE: IMPORTANT we set the rate provider as address(0) and pegged for all assets
        for (uint256 i; i < params.withdrawAssets.length; ++i) {
            teller2.addWithdrawAsset(ERC20(params.withdrawAssets[i]));
            accountant2.setRateProviderData(ERC20(params.withdrawAssets[i]), true, address(0));
        }

        // Set the Role Capabilities for the new Teller
        params.authority
            .setRoleCapability(DEPOSITOR_ROLE, address(teller2), TellerWithMultiAssetSupport.deposit.selector, true);
        params.authority
            .setRoleCapability(
                DEPOSITOR_ROLE, address(teller2), TellerWithMultiAssetSupport.depositWithPermit.selector, true
            );
        params.authority
            .setRoleCapability(PAUSER_ROLE, address(teller2), TellerWithMultiAssetSupport.pause.selector, true);
        params.authority
            .setRoleCapability(SOLVER_ROLE, address(teller2), TellerWithMultiAssetSupport.bulkWithdraw.selector, true);
        // Grant the TELLER ROLE to the teller2 contract
        params.authority.setUserRole(address(teller2), TELLER_ROLE, true);

        // Deploy the DistributorCodeDepositor
        // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

        // NOTE: Unlike other contracts, we set the owner to the multisig directly as we do not need any further actions
        // to be completed
        dcd2 = DistributorCodeDepositor(
            CREATEX.deployCreate3(
                _makeSalt(false, symbol, "DistributorCodeDepositorRedEnvelope"),
                abi.encodePacked(
                    type(DistributorCodeDepositor).creationCode,
                    abi.encode(address(teller2), address(0), params.authority, false, multisig)
                )
            )
        );

        // Set public capabilities for the distributor code depositor
        params.authority.setPublicCapability(address(dcd2), DistributorCodeDepositor.deposit.selector, true);
        params.authority.setPublicCapability(address(dcd2), DistributorCodeDepositor.depositWithPermit.selector, true);

        // Deploy the Simple Fee Module
        // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        feeModule = SimpleFeeModule(
            CREATEX.deployCreate3(
                _makeSalt(false, symbol, "FeeModuleRedEnvelope"),
                abi.encodePacked(type(SimpleFeeModule).creationCode, abi.encode(params.offerFeePercentage))
            )
        );

        // Deploy the Withdraw Queue
        // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        // NOTE: We set the owner to this flash-upgrade contract for now
        withdrawQueue = WithdrawQueue(
            CREATEX.deployCreate3(
                _makeSalt(false, symbol, "WithdrawQueueRedEnvelope"),
                abi.encodePacked(
                    type(WithdrawQueue).creationCode,
                    abi.encode(
                        params.queueErc721Name,
                        params.queueErc721Symbol,
                        params.queueFeeRecipient,
                        address(teller2),
                        address(feeModule),
                        params.minimumOrderSize,
                        address(this)
                    )
                )
            )
        );

        // Set the Authority of the new withdraw queue
        withdrawQueue.setAuthority(params.authority);

        // Set the Role Capabilities for the new withdraw queue
        params.authority
            .setRoleCapability(
                WITHDRAW_QUEUE_PROCESSOR_ROLE, address(withdrawQueue), WithdrawQueue.processOrders.selector, true
            );

        // Grant the processor role to the processor address
        params.authority.setUserRole(params.withdrawQueueProcessorAddress, WITHDRAW_QUEUE_PROCESSOR_ROLE, true);
        params.authority.setUserRole(address(withdrawQueue), SOLVER_ROLE, true);

        // Grant public capabilities to the withdraw queue
        params.authority.setPublicCapability(address(withdrawQueue), WithdrawQueue.submitOrder.selector, true);
        params.authority.setPublicCapability(address(withdrawQueue), WithdrawQueue.cancelOrder.selector, true);
        params.authority
            .setPublicCapability(address(withdrawQueue), WithdrawQueue.cancelOrderWithSignature.selector, true);

        // Return the ownership of the contracts
        // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
        params.authority.transferOwnership(msg.sender);
        params.accountant1.transferOwnership(msg.sender);
        accountant2.transferOwnership(msg.sender);
        teller2.transferOwnership(msg.sender);
        withdrawQueue.transferOwnership(msg.sender);
    }

    /**
     * @dev a CREATEX helper to make a salt programatically
     */
    function _makeSalt(
        bool isCrosschainProtected,
        string memory symbol,
        string memory nameEntropy
    )
        internal
        view
        returns (bytes32)
    {
        bytes1 crosschainProtectionFlag = isCrosschainProtected ? bytes1(0x01) : bytes1(0x00);
        bytes32 nameEntropyHash = keccak256(abi.encodePacked(symbol, nameEntropy));
        bytes11 nameEntropyHash11 = bytes11(nameEntropyHash);
        return bytes32(abi.encodePacked(address(this), crosschainProtectionFlag, nameEntropyHash11));
    }

}
