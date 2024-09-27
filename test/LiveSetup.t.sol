// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { DeployAll } from "script/deploy/deployAll.s.sol";
import { ConfigReader } from "script/ConfigReader.s.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { DeployRateProviders } from "script/deploy/01_DeployRateProviders.s.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";

import { CrossChainOPTellerWithMultiAssetSupportTest } from
    "test/CrossChain/CrossChainOPTellerWithMultiAssetSupport.t.sol";
import { CrossChainTellerBase, BridgeData, ERC20 } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { CrossChainOPTellerWithMultiAssetSupport } from
    "src/base/Roles/CrossChain/CrossChainOPTellerWithMultiAssetSupport.sol";
import { MultiChainLayerZeroTellerWithMultiAssetSupport } from
    "src/base/Roles/CrossChain/MultiChainLayerZeroTellerWithMultiAssetSupport.sol";

string constant DEFAULT_RPC_URL = "L1_RPC_URL";
uint256 constant DELTA = 10_000;

// We use this so that we can use the inheritance linearization to start the fork before other constructors
abstract contract ForkTest is Test {
    constructor() {
        // the start fork must be done before the constructor in the Base.s.sol, as it attempts to access an onchain
        // asset, CREATEX
        _startFork(DEFAULT_RPC_URL);
    }

    function _startFork(string memory rpcKey) internal virtual returns (uint256 forkId) {
        if (block.chainid == 31_337) {
            forkId = vm.createFork(vm.envString(rpcKey));
            vm.selectFork(forkId);
        }
    }
}

abstract contract LiveSetup is ForkTest, DeployAll {
    using Strings for address;
    using StdJson for string;

    ERC20 constant NATIVE_ERC20 = ERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    uint256 ONE_SHARE;
    uint8 constant SOLVER_ROLE = 42;

    function setUp() public virtual {
        string memory FILE_NAME;

        // 31_337 is default if this script is ran with no --fork-url= CLI flag
        // when using the Makefile we use this flag to simplify use of the makefile
        // however, the script should still have a default configuration for fork and FILE_NAME
        if (block.chainid == 31_337) {
            // default file is exampleL1
            FILE_NAME = "exampleL1.json";

            // we have to start the fork again... I don't exactly know why. But it's a known issue with foundry re:
            // https://github.com/foundry-rs/foundry/issues/5471
            _startFork(DEFAULT_RPC_URL);
        } else {
            // Otherwise we use the makefile provided deployment file ENV name
            FILE_NAME = vm.envString("LIVE_DEPLOY_READ_FILE_NAME");
        }

        // Run the deployment scripts

        run(FILE_NAME);

        // check for if all rate providers are deployed, if not error
        for (uint256 i; i < mainConfig.assets.length; ++i) {
            // set the corresponding rate provider
            string memory key = string(
                abi.encodePacked(
                    ".assetToRateProviderAndPriceFeed.", mainConfig.assets[i].toHexString(), ".rateProvider"
                )
            );

            address rateProvider = getChainConfigFile().readAddress(key);
            assertNotEq(rateProvider, address(0), "Rate provider address is 0");
            assertNotEq(rateProvider.code.length, 0, "No code at rate provider address");
        }

        // warp forward the minimumUpdateDelay for the accountant to prevent it from pausing on update test
        vm.warp(block.timestamp + mainConfig.minimumUpdateDelayInSeconds);

        // define one share based off of vault decimals
        ONE_SHARE = 10 ** BoringVault(payable(mainConfig.boringVault)).decimals();

        // give this the SOLVER_ROLE to call bulkWithdraw
        RolesAuthority rolesAuthority = RolesAuthority(mainConfig.rolesAuthority);
        vm.startPrank(mainConfig.protocolAdmin);
        rolesAuthority.setUserRole(address(this), SOLVER_ROLE, true);
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, mainConfig.teller, TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        vm.stopPrank();
    }
}
