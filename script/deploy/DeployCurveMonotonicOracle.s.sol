// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { MonotonicExchangeRateOracle } from "src/oracles/MonotonicExchangeRateOracle.sol";
import { OracleRelay } from "src/helper/OracleRelay.sol";
import { BaseScript } from "../Base.s.sol";
import { console } from "forge-std/console.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";

contract DeployCurveMonotonicOracle is BaseScript {

    address multisig = 0x413f2e80070a069eB1051772Fdc4f0af8e8303d7;
    // accountant for WHLP
    AccountantWithRateProviders accountant = AccountantWithRateProviders(0x470bd109A24f608590d85fc1f5a4B6e625E8bDfF);

    function run() public broadcast {
        require(block.chainid == 999, "This script can only be run on hyperevm");
        MonotonicExchangeRateOracle oracle = new MonotonicExchangeRateOracle(multisig, accountant);
        OracleRelay relay = new OracleRelay(broadcaster);
        relay.setImplementation(address(oracle));
        relay.transferOwnership(multisig);

        assert(address(oracle.owner()) == multisig);
        assert(address(relay.owner()) == multisig);
        // We assert the oracle rate = accountant.getRate() * 10**12 since the accountant oracle returns in 6 decimals
        // While the curve oracle must return in 18
        assert(relay.getRate() == accountant.getRate() * 10 ** (18 - accountant.decimals()));
        console.log("CurveMonotonicOracle deployed at", address(oracle));
        console.log("OracleRelay deployed at", address(relay));
    }

}
