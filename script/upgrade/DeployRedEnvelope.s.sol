// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseScript } from "../Base.s.sol";
import { RedEnvelopeUpgrade, CONTRACT } from "src/helper/upgrade/RedEnvelope.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { DistributorCodeDepositor } from "src/helper/DistributorCodeDepositor.sol";
import { WithdrawQueue } from "src/base/Roles/WithdrawQueue.sol";
import { SimpleFeeModule } from "src/helper/one-to-one-queue/SimpleFeeModule.sol";

contract DeployRedEnvelope is BaseScript {

    function run() public returns (address redEnvelope) {
        return deploy();
    }

    function deploy() public broadcast returns (address) {
        address createx = address(CREATEX);
        address multisig = getMultisig();

        // Deploy RedEnvelope with minimal constructor (deployer is owner)
        RedEnvelopeUpgrade redEnvelopeUpgrade = new RedEnvelopeUpgrade(createx, multisig);

        // Deployer sets creation code for each contract (deployer is owner)
        redEnvelopeUpgrade.setContractCreationCode(CONTRACT.ACCOUNTANT2, type(AccountantWithRateProviders).creationCode);
        redEnvelopeUpgrade.setContractCreationCode(CONTRACT.TELLER2, type(TellerWithMultiAssetSupport).creationCode);
        redEnvelopeUpgrade.setContractCreationCode(CONTRACT.DCD2, type(DistributorCodeDepositor).creationCode);
        redEnvelopeUpgrade.setContractCreationCode(CONTRACT.WITHDRAW_QUEUE, type(WithdrawQueue).creationCode);
        redEnvelopeUpgrade.setContractCreationCode(CONTRACT.FEE_MODULE, type(SimpleFeeModule).creationCode);

        // Transfer owner role to multisig so it can update creation code later if needed
        redEnvelopeUpgrade.transferOwnership(multisig);

        return address(redEnvelopeUpgrade);
    }

}
