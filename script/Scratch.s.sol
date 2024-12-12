// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ArcticArchitectureLens } from "src/helper/ArcticArchitectureLens.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import "@forge-std/Script.sol";
import "@forge-std/StdJson.sol";

/**
 *  source .env && forge script script/DeployLens.s.sol:DeployLensScript --with-gas-price 30000000000 --slow --broadcast
 * --etherscan-api-key $ETHERSCAN_KEY --verify
 * @dev Optionally can change `--with-gas-price` to something more reasonable
 */
contract ScratchScript is Script {
    uint256 public privateKey;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
    }

    function run() external {
        vm.startBroadcast(privateKey);

        TellerWithMultiAssetSupport pUsdTeller = TellerWithMultiAssetSupport(0xE010B6fdcB0C1A8Bf00699d2002aD31B4bf20B86);
        AccountantWithRateProviders pUsdAccountant =
            AccountantWithRateProviders(0x607e6E4dC179Bf754f88094C09d9ee9Af990482a);

        TellerWithMultiAssetSupport yieldTeller =
            TellerWithMultiAssetSupport(0x76336e10Cd5A162656F7Dff6aBDBC4aD43c33296);
        AccountantWithRateProviders yieldAccountant =
            AccountantWithRateProviders(0x2176CA0C6Af52B8D39131d633A1D3B37B115c272);

        TellerWithMultiAssetSupport tbillTeller =
            TellerWithMultiAssetSupport(0xd660207ffF6052a667576554C747E56630e902b4);
        AccountantWithRateProviders tbillAccountant =
            AccountantWithRateProviders(0xa4D7cE39e45646CDD04299f9006fD9605bbb5F2B);

        ERC20 pUSD = ERC20(0x2DEc3B6AdFCCC094C31a2DCc83a43b5042220Ea2);

        pUsdTeller.addAsset(pUSD);
        pUsdAccountant.setRateProviderData(pUSD, true, address(0));

        // yieldTeller.addAsset(pUSD);
        // yieldAccountant.setRateProviderData(pUSD, true, address(0));

        // tbillTeller.addAsset(pUSD);
        // tbillAccountant.setRateProviderData(pUSD, true, address(0));

        vm.stopBroadcast();
    }
}
