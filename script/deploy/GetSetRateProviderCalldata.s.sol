// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { ManagerWithMerkleVerification } from "./../../../src/base/Roles/ManagerWithMerkleVerification.sol";
import { BoringVault } from "./../../../src/base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "./../../../src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "./../../../src/base/Roles/AccountantWithRateProviders.sol";
import { RateProviderConfig } from "./../../../src/base/Roles/RateProviderConfig.sol";
import { BaseScript } from "script/Base.s.sol";
import { ConfigReader } from "script/ConfigReader.s.sol";
import { CrossChainTellerBase } from "../../../src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { console } from "@forge-std/console.sol";

/**
 * @dev Contract to get the calldata for setting rate provider data
 * Since this is done in a multisig, we can't automate it with the scripts.
 * But we can use the script to generate calldata for pasting into SAFE
 */
contract GetSetRateProviderCalldata is BaseScript {
    using Strings for address;
    using StdJson for string;
    using Strings for uint256;

    function run() external returns (bytes[] memory setRateProviderCalldata) {
        ConfigReader.Config memory config = getConfig();
        string memory _chainConfig = getChainConfigFile();

        setRateProviderCalldata = _getSetRateProviderCalldata(config, _chainConfig);
    }

    function run(ConfigReader.Config memory config) external returns (bytes[] memory setRateProviderCalldata) {
        string memory _chainConfig = getChainConfigFile();
        setRateProviderCalldata = _getSetRateProviderCalldata(config, _chainConfig);
    }

    function _getSetRateProviderCalldata(
        ConfigReader.Config memory config,
        string memory _chainConfig
    )
        internal
        returns (bytes[] memory setRateProviderCalldata)
    {
        TellerWithMultiAssetSupport teller = TellerWithMultiAssetSupport(config.teller);
        RateProviderConfig rateProviderContract = RateProviderConfig(config.rateProvider);

        uint256 len = config.assets.length + 1;
        ERC20[] memory assets = new ERC20[](len);
        assets[0] = ERC20(config.base);

        // Rate providerCalldata crucially does not include the base as an asset to fetch
        setRateProviderCalldata = new bytes[](config.assets.length);

        for (uint256 i; i < config.assets.length; ++i) {
            // add asset
            assets[i + 1] = ERC20(config.assets[i]);

            string memory assetKey =
                string(abi.encodePacked(".assetToRateProviderAndPriceFeed.", config.assets[i].toHexString()));

            uint256 length = _chainConfig.readUint(string(abi.encodePacked(assetKey, ".numberOfRateProviders")));
            RateProviderConfig.RateProviderData[] memory rateProviderData =
                new RateProviderConfig.RateProviderData[](length);

            for (uint256 j; j < length; ++j) {
                rateProviderData[j] = _getRateProviderData(assetKey, j, _chainConfig);
            }

            setRateProviderCalldata[i] = abi.encodeWithSelector(
                RateProviderConfig.setRateProviderData.selector,
                ERC20(config.base),
                ERC20(config.assets[i]),
                rateProviderData
            );
            console.log("Set RateProviderCalldata: ");
            console.logBytes(setRateProviderCalldata[i]);
        }
    }

    function _getRateProviderData(
        string memory assetKey,
        uint256 index,
        string memory _chainConfig
    )
        internal
        view
        returns (RateProviderConfig.RateProviderData memory data)
    {
        string memory rateProviderKey = string(abi.encodePacked(assetKey, ".rateProviders[", index.toString(), "]"));
        address rateProvider = _chainConfig.readAddress(string(abi.encodePacked(rateProviderKey, ".target")));

        bytes memory rateCalldata = _chainConfig.readBytes(string(abi.encodePacked(rateProviderKey, ".calldata")));

        bool isPeggedToBase;
        if (rateProvider == address(0) && rateCalldata.length == 0) {
            isPeggedToBase = true;
        } else {
            require(rateProvider != address(0), "rate provider must be set");
            require(rateProvider.code.length > 0, "rate provider must have code");
            require(rateCalldata.length > 0, "calldata must be set");
        }

        data.isPeggedToBase = isPeggedToBase;
        data.rateProvider = rateProvider;
        data.functionCalldata = rateCalldata;
        data.minRate = _chainConfig.readUint(string(abi.encodePacked(assetKey, ".expectedMin")));
        data.maxRate = _chainConfig.readUint(string(abi.encodePacked(assetKey, ".expectedMax")));
    }
}
