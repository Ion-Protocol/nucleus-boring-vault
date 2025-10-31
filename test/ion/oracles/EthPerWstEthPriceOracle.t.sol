// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { EthPerWstEthRateProvider } from "./../../../src/oracles/EthPerWstEthRateProvider.sol";
import { ETH_PER_STETH_CHAINLINK, WSTETH_ADDRESS } from "@ion-protocol/Constants.sol";
import { Test } from "@forge-std/Test.sol";

contract EthPerWstEthRateProviderTest is Test {

    uint256 MAX_TIME_FROM_LAST_UPDATE = 1 days;
    EthPerWstEthRateProvider ethPerWstEthRateProvider;

    function setUp() public {
        string memory rpcKey = "MAINNET_RPC_URL";
        uint256 blockNumber = 19_827_152;
        _startFork(rpcKey, blockNumber);

        ethPerWstEthRateProvider = new EthPerWstEthRateProvider(
            address(ETH_PER_STETH_CHAINLINK), address(WSTETH_ADDRESS), MAX_TIME_FROM_LAST_UPDATE
        );
    }

    function test_Revert_MaxTimeFromLastUpdate() public {
        (,,, uint256 lastUpdatedAt,) = ETH_PER_STETH_CHAINLINK.latestRoundData(); // price of stETH denominated in ETH

        ethPerWstEthRateProvider.getRate();

        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                EthPerWstEthRateProvider.MaxTimeFromLastUpdatePassed.selector, block.timestamp, lastUpdatedAt
            )
        );
        ethPerWstEthRateProvider.getRate();
    }

    function _startFork(string memory rpcKey, uint256 blockNumber) internal returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }

}
