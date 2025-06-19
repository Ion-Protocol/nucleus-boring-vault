// SPDX-License-Identifier: BUSL-1.1

import { HyperliquidForwarder } from "src/helper/HyperliquidForwarder.sol";
import { BaseScript } from "../Base.s.sol";
import { console } from "forge-std/console.sol";

contract DeployHyperliquidForwarder is BaseScript {
    address multisigHyperliquid = 0x413f2e80070a069eB1051772Fdc4f0af8e8303d7;

    function run() public broadcast {
        require(block.chainid == 999, "Deployment script only supports Hyperliquid mainnet");

        // Deploy the forwarder, with broadcaster as the owner for now
        HyperliquidForwarder forwarder = new HyperliquidForwarder(broadcaster);

        // config accepted senders
        forwarder.setSenderAllowStatus(0xfeed5E39663aF7ECedeed464D0e221afA559768c, true);

        // config accepted EOAs
        forwarder.setEOAAllowStatus(0x9fcB7066C8AeEe704f9D017996b490873b306E51, true);

        // config accepted assets and bridges
        address USDT = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
        uint16 USDTID = 166;
        address USDTBridge = 0x20000000000000000000000000000000000000A6;
        address USDHL = 0xb50A96253aBDF803D85efcDce07Ad8becBc52BD5;
        uint16 USDHLID = 180;
        address USDHLBridge = 0x20000000000000000000000000000000000000B4;

        forwarder.addTokenIDToBridgeMapping(USDT, USDTBridge, USDTID);
        forwarder.addTokenIDToBridgeMapping(USDHL, USDHLBridge, USDHLID);

        // set owner as the multisigHyperliquid
        // forwarder.transferOwnership(multisigHyperliquid);
        console.log("NOTE: OWNER IS DEPLOYER | If using in prod, please transfer to multisig");

        console.log("Forwarder address: ", address(forwarder));
    }
}
