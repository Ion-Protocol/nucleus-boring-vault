// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ArcticArchitectureLens } from "src/helper/ArcticArchitectureLens.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { CrossChainTellerBase, BridgeData } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import "@forge-std/Script.sol";
import "@forge-std/StdJson.sol";

import { console2 } from "forge-std/console2.sol";

contract TellerDepositScript is Script {
    address constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 public privateKey;

    function setUp() external {
        privateKey = vm.envUint("PRIVATE_KEY");
    }

    function run() external {
        vm.startBroadcast(privateKey);
        BoringVault vault = BoringVault(payable(0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F));
        CrossChainTellerBase teller = CrossChainTellerBase(0x16424eDF021697E34b800e1D98857536B0f2287B);
        BridgeData memory data;
        data.chainSelector = 30_318;
        data.destinationChainReceiver = 0x04354e44ed31022716e77eC6320C04Eda153010c;
        data.bridgeFeeToken = ERC20(NATIVE);
        data.messageGas = 100_000;
        data.data = "";

        ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        USDC.approve(address(teller.vault()), 100e6);
        uint256 amt = 1e6;

        uint256 fee = teller.previewFee(amt, data);
        console2.log("fee: ", fee);

        teller.depositAndBridge{ value: fee }(USDC, amt, amt, data);

        vm.stopBroadcast();
    }
}

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
