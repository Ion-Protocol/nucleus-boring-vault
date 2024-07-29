// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {RolesAuthority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ManagerWithMerkleVerification} from "./../../../src/base/Roles/ManagerWithMerkleVerification.sol";
import {BoringVault} from "./../../../src/base/BoringVault.sol";
import {TellerWithMultiAssetSupport} from "./../../../src/base/Roles/TellerWithMultiAssetSupport.sol";
import {AccountantWithRateProviders} from "./../../../src/base/Roles/AccountantWithRateProviders.sol";
import {BaseScript} from "../../Base.s.sol";
import {ConfigReader} from "../../ConfigReader.s.sol";
import {CrossChainTellerBase} from "../../../src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

contract TellerSetup is BaseScript {

    function run() public virtual {
        deploy(getConfig());
    }

    function deploy(ConfigReader.Config memory config) public virtual override broadcast returns(address){
        TellerWithMultiAssetSupport teller = TellerWithMultiAssetSupport(config.teller);

        teller.addAsset(ERC20(config.base));
        AccountantWithRateProviders(teller.accountant()).setRateProviderData(ERC20(config.base), true, config.rateProvider);
    }
}
