// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseScript } from "../Base.s.sol";
import { RedEnvelopeUpgrade } from "src/helper/upgrade/RedEnvelope.sol";
import { IAccountantWithRateProviders } from "src/interfaces/Roles/IAccountantWithRateProviders.sol";
import { ITellerWithMultiAssetSupport } from "src/interfaces/Roles/ITellerWithMultiAssetSupport.sol";
import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { console } from "@forge-std/Console.sol";

/**
 * Generates calldata for the multisig to call RedEnvelope.flashUpgrade(...) and simulates the call as multisig.
 *
 * Pre-upgrade contract addresses (from comments):
 *   Boring Vault: 0x5928965EcF96386aAe2CDfa592Ff68f7e54832D4
 *   Manager: 0x10cCCdCdD937731206736d5dB65F2402E919778f
 *   Accountant: 0xFE01b0becc666b50b43d368dCbd55577f6187824
 *   Teller: 0x738F9744a0EdE4307aAc5b4Ed0B046bc38e61fCB
 *   Roles Authority: 0xbCE0FeEb3523A5D81C01F66A9b41f580A71FA8d3
 *   Distributor Code: 0x23EB97cD68378708E1AC7f69EF8ddF2E56c591cE
 *
 * For simulation to succeed, run on a fork after RedEnvelope is deployed and ownership of
 * Accountant and Roles Authority has been transferred to the RedEnvelope contract.
 */
contract GenerateRedEnvelopeCalldata is BaseScript {

    function run() public {
        address redEnvelopeAddress = 0xEcF917f182Fd9D9f4775A4BF3950C94E6dab9f65;
        address multisig = getMultisig();

        // Build FlashUpgradeParams from the specified values
        address[] memory depositAssets = new address[](1);
        depositAssets[0] = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        address[] memory withdrawAssets = new address[](1);
        withdrawAssets[0] = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

        RedEnvelopeUpgrade.FlashUpgradeParams memory params = RedEnvelopeUpgrade.FlashUpgradeParams({
            accountant1: IAccountantWithRateProviders(0xFE01b0becc666b50b43d368dCbd55577f6187824),
            teller1: ITellerWithMultiAssetSupport(0x738F9744a0EdE4307aAc5b4Ed0B046bc38e61fCB),
            authority: RolesAuthority(0xbCE0FeEb3523A5D81C01F66A9b41f580A71FA8d3),
            accountantPerformanceFee: 2000, // 20% (basis points, 1e4 = 100%)
            offerFeePercentage: 2, // 0.02% (basis points)
            depositAssets: depositAssets,
            withdrawAssets: withdrawAssets,
            withdrawQueueProcessorAddress: 0xCb8FA722B2a138faC6B6D60013025E2504b9B753,
            queueFeeRecipient: multisig,
            minimumOrderSize: 10e6,
            queueErc721Name: "unTEST",
            queueErc721Symbol: "unTEST"
        });

        // Encode calldata for Gnosis Safe: target = RedEnvelope, data = flashUpgrade(params)
        bytes memory calldataBytes = abi.encodeWithSelector(RedEnvelopeUpgrade.flashUpgrade.selector, params);

        // Log target and calldata for Safe UI
        console.log("=== For Gnosis Safe UI ===");
        console.log("Target (RedEnvelope):", redEnvelopeAddress);
        console.log("Calldata (hex):");
        console.logBytes(calldataBytes);

        // Simulate ownership transfers and flashUpgrade as the multisig
        vm.startPrank(multisig);
        // Simulate transferring accountant1 ownership to RedEnvelope (required for flashUpgrade)
        params.accountant1.transferOwnership(redEnvelopeAddress);
        // Simulate transferring Roles Authority ownership to RedEnvelope (required for flashUpgrade)
        params.authority.transferOwnership(redEnvelopeAddress);
        // flashUpgrade can only be called by multisig
        RedEnvelopeUpgrade(redEnvelopeAddress).flashUpgrade(params);
        vm.stopPrank();
    }

}
