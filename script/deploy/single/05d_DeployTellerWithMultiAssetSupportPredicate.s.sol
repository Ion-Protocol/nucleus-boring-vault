// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AccountantWithRateProviders } from "./../../../src/base/Roles/AccountantWithRateProviders.sol";
import { TellerWithMultiAssetSupportPredicate } from
    "./../../../src/base/Roles/TellerWithMultiAssetSupportPredicate.sol";
import { MainnetAddresses } from "./../../../test/resources/MainnetAddresses.sol";
import { BaseScript } from "./../../Base.s.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { ConfigReader } from "../../ConfigReader.s.sol";

contract DeployTellerWithMultiAssetSupportPredicate is BaseScript, MainnetAddresses {
    using StdJson for string;

    function run() public returns (address) {
        return deploy(getConfig());
    }

    function deploy(ConfigReader.Config memory config) public override broadcast returns (address) {
        // Require config Values
        require(config.boringVault.code.length != 0, "boringVault must have code");
        require(config.accountant.code.length != 0, "accountant must have code");
        require(config.tellerSalt != bytes32(0), "tellerSalt");
        require(config.boringVault != address(0), "boringVault");
        require(config.accountant != address(0), "accountant");
        string memory _policyID = "x-strict-membership-policy";
        address _serviceManager = 0xcb397f4bDF93213851Ef1c84439Dd3497Dff66c1;

        // Create Contract
        bytes memory creationCode = type(TellerWithMultiAssetSupportPredicate).creationCode;
        TellerWithMultiAssetSupportPredicate teller = TellerWithMultiAssetSupportPredicate(
            CREATEX.deployCreate3(
                config.tellerSalt,
                abi.encodePacked(
                    creationCode,
                    abi.encode(broadcaster, config.boringVault, config.accountant, _serviceManager, _policyID)
                )
            )
        );

        // Post Deploy Checks
        require(teller.shareLockPeriod() == 0, "share lock period must be zero");
        require(teller.isPaused() == false, "the teller must not be paused");
        require(
            AccountantWithRateProviders(teller.accountant()).vault() == teller.vault(),
            "the accountant vault must be the teller vault"
        );

        return address(teller);
    }
}
