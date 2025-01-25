// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { ManagerWithMerkleVerification } from "./../../../src/base/Roles/ManagerWithMerkleVerification.sol";
import { BoringVault } from "./../../../src/base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "./../../../src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "./../../../src/base/Roles/AccountantWithRateProviders.sol";
import { BaseScript } from "../../Base.s.sol";
import { ConfigReader } from "../../ConfigReader.s.sol";
import { CrossChainTellerBase } from "../../../src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";

contract TellerSetup is BaseScript {
    using Strings for address;
    using StdJson for string;

    function run() public virtual {
        deploy(getConfig());
    }

    function deploy(ConfigReader.Config memory config) public virtual override broadcast returns (address) {
        TellerWithMultiAssetSupport teller = TellerWithMultiAssetSupport(config.teller);

        uint256 len = config.assets.length + 1;
        ERC20[] memory assets = new ERC20[](len);
        assets[0] = ERC20(config.base);

        uint112[] memory rateLimits = new uint112[](len);
        rateLimits[0] = type(uint112).max;

        bool[] memory withdrawStatusByAssets = new bool[](len);
        withdrawStatusByAssets[0] = true;

        // add the remaining assets specified in the assets array of config
        for (uint256 i; i < config.assets.length; ++i) {
            assets[i] = ERC20(config.assets[i]);
            withdrawStatusByAssets[i] = true;

            // set the corresponding rate provider
            string memory key = string(
                abi.encodePacked(".assetToRateProviderAndPriceFeed.", config.assets[i].toHexString(), ".rateProvider")
            );
            address rateProvider = getChainConfigFile().readAddress(key);
            teller.accountant().setRateProviderData(ERC20(config.assets[i]), false, rateProvider);
        }

        teller.configureAssets(assets, rateLimits, withdrawStatusByAssets);
    }
}
