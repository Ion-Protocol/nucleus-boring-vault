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
        forwarder.setSenderAllowStatus(0x1359b05241cA5076c9F59605214f4F84114c0dE8, true);

        // config accepted EOAs
        forwarder.setEOAAllowStatus(0x9fcB7066C8AeEe704f9D017996b490873b306E51, true);
        forwarder.setEOAAllowStatus(0x41f45A847bB6c8bFf1448FEE5C9525875D443b9E, true);
        forwarder.setEOAAllowStatus(0x296B1078D860c69C94CA933c4BcD2d6f192DD86e, true);
        forwarder.setEOAAllowStatus(0x31Cbd708B505d3A9A0dae336BC9476b694256e74, true);
        forwarder.setEOAAllowStatus(0xFBB47621086901487C7f3beC6F23205738d59e27, true);

        // config accepted assets and bridges
        address USDT = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
        uint16 USDTID = 268;
        address USDTBridge = 0x200000000000000000000000000000000000010C;
        address USDHL = 0xb50A96253aBDF803D85efcDce07Ad8becBc52BD5;
        uint16 USDHLID = 291;
        address USDHLBridge = 0x2000000000000000000000000000000000000123;

        forwarder.addTokenIDToBridgeMapping(USDT, USDTBridge, USDTID);
        forwarder.addTokenIDToBridgeMapping(USDHL, USDHLBridge, USDHLID);

        // set owner as the multisigHyperliquid
        forwarder.transferOwnership(multisigHyperliquid);
        // console.log("NOTE: OWNER IS DEPLOYER | If using in prod, please transfer to multisig");

        console.log("Forwarder address: ", address(forwarder));
    }

}
