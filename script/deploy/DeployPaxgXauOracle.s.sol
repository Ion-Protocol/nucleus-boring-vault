// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { PaxgXauRateProvider } from "src/oracles/PaxgXauRateProvider.sol";
import { IPriceFeed } from "src/interfaces/IPriceFeed.sol";
import { BaseScript } from "../Base.s.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { console2 } from "forge-std/console2.sol";

using StdJson for string;

/**
 * @notice Deploys the {PaxgXauRateProvider} composite oracle (XAU per PAXG) via CreateX CREATE3.
 * @dev The Chainlink PAXG/USD and XAU/USD feeds only exist on Ethereum mainnet, so deployment is
 * gated to chain id 1. The constructor validates each feed's `description()`, so a mistyped feed
 * address will cause the deployment to revert rather than silently wire the wrong source.
 */
contract DeployPaxgXauOracle is BaseScript {

    // Deployer protected: 0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f
    bytes32 constant SALT = 0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f005555555555555555550901;

    // Chainlink Ethereum mainnet feeds. Verify against docs.chain.link before broadcasting.
    address constant PAXG_USD_FEED = 0x9944D86CEB9160aF5C5feB251FD671923323f8C3;
    address constant XAU_USD_FEED = 0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6;

    // PAXG token (18 decimals); its decimals define the oracle's output precision.
    address constant PAXG_TOKEN = 0x45804880De22913dAFE09f4980848ECE6EcbAf78;

    string constant PAXG_USD_DESCRIPTION = "PAXG / USD";
    string constant XAU_USD_DESCRIPTION = "XAU / USD";

    // The Chainlink PAXG/USD feed's heartbeat is 86400s (24h); we add 100s to account for block delay.
    uint256 constant MAX_TIME_FROM_LAST_UPDATE = 86_500;

    function run() public broadcast {
        if (block.chainid != 1) {
            revert("PAXG/XAU Chainlink feeds are only deployed on Ethereum mainnet (chainid 1)");
        }

        bytes memory creationCode = type(PaxgXauRateProvider).creationCode;

        address rateProvider = CREATEX.deployCreate3(
            SALT,
            abi.encodePacked(
                creationCode,
                abi.encode(
                    PAXG_USD_DESCRIPTION,
                    XAU_USD_DESCRIPTION,
                    ERC20(PAXG_TOKEN),
                    IPriceFeed(PAXG_USD_FEED),
                    IPriceFeed(XAU_USD_FEED),
                    MAX_TIME_FROM_LAST_UPDATE
                )
            )
        );

        console2.log("PaxgXauRateProvider: ", rateProvider);
    }

}
