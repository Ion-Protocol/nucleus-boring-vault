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
    using Strings for uint256;

    function run() public virtual {
        deploy(getConfig());
    }

    function deploy(ConfigReader.Config memory config) public virtual override broadcast returns (address) {
        string memory _chainConfig = getChainConfigFile();

        TellerWithMultiAssetSupport teller = TellerWithMultiAssetSupport(config.teller);

        uint256 len = config.assets.length + 1;
        ERC20[] memory assets = new ERC20[](len);
        assets[0] = ERC20(config.base);

        for (uint256 i; i < config.assets.length; ++i) {
            // add asset
            assets[i + 1] = ERC20(config.assets[i]);

            string memory assetKey =
                string(abi.encodePacked(".assetToRateProviderAndPriceFeed.", config.assets[i].toHexString()));

            uint256 length = _chainConfig.readUint(string(abi.encodePacked(assetKey, ".numberOfRateProviders")));
            AccountantWithRateProviders.RateProviderData[] memory rateProviderData =
                new AccountantWithRateProviders.RateProviderData[](length);

            for (uint256 j; j < length; ++j) {
                string memory rateProviderKey = string(abi.encodePacked(assetKey, ".rateProviders[", j.toString(), "]"));
                address rateProvider = _chainConfig.readAddress(string(abi.encodePacked(rateProviderKey, ".target")));

                bytes memory rateCalldata =
                    _chainConfig.readBytes(string(abi.encodePacked(rateProviderKey, ".calldata")));

                bool isPeggedToBase;
                if (rateProvider == address(0) && rateCalldata.length == 0) {
                    isPeggedToBase = true;
                } else {
                    require(rateProvider != address(0), "rate provider must be set");
                    require(rateProvider.code.length > 0, "rate provider must have code");
                    require(rateCalldata.length > 0, "calldata must be set");
                }

                rateProviderData[j].isPeggedToBase = isPeggedToBase;
                rateProviderData[j].rateProvider = rateProvider;
                rateProviderData[j].functionCalldata = rateCalldata;
            }

            teller.accountant().setRateProviderData(ERC20(config.assets[i]), rateProviderData);
        }
        teller.addAssets(assets);
    }
}
