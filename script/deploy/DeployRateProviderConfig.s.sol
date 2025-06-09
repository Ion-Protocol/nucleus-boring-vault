// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { RateProviderConfig } from "./../../../src/base/Roles/RateProviderConfig.sol";
import { BaseScript } from "../Base.s.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

using StdJson for string;

// NOTE Currently assumes that function signature arguments are empty.
contract DeployRateProviderConfig is BaseScript {
    RateProviderConfig rateProvider;

    // deployer:            0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f00
    bytes32 constant SALT = 0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f00fcdbd6afdd472179b79b16;
    address multisig = 0x0000000000417626Ef34D62C4DC189b021603f2F;

    function run() public broadcast {
        require(multisig != address(0), "Multisig must not be set to 0 address");
        vm.prompt(
            string.concat(
                "You are about to deploy a Rate Provider Config on\nchainID ",
                vm.toString(block.chainid),
                "\nowner being set to: ",
                vm.toString(multisig),
                "\nThe rate provider data will be set according to the chain config file for this chain. In the future the multisig must update these configurations",
                "\nPlease double check these values and press ENTER to continue"
            )
        );

        bytes memory creationCode = type(RateProviderConfig).creationCode;

        // TODO: Set to deployer as owner
        rateProvider =
            RateProviderConfig(CREATEX.deployCreate3(SALT, abi.encodePacked(creationCode, abi.encode(broadcaster))));

        // TODO: Set default rate provider data according to the chain Config
        _configETH();

        // TODO: Transfer ownership back to the multisig
        rateProvider.transferOwnership(multisig);
    }

    /*
    * DEFAULT CONFIGS FOR EACH CHAIN
    */
    function _configETH() internal {
        address base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        // stETH/wstETH
        address asset = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        RateProviderConfig.RateProviderData memory data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            functionCalldata: hex"035faf82",
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });
        RateProviderConfig.RateProviderData[] memory input = new RateProviderConfig.RateProviderData[](1);
        input[0] = data;

        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        //eeETH/weETH
        asset = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee,
            functionCalldata: abi.encodeWithSignature("getEETHByWeETH(uint256)", 1_000_000_000_000_000_000),
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });
        input[0] = data;

        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // ETH/ezETH
        asset = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0x3239396B740cD6BBABb42196A03f7B77fA7102C9,
            functionCalldata: hex"f13597a6",
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });
        input[0] = data;

        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // ETH/rsETH
        asset = 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0x349A73444b1a310BAe67ef67973022020d70020d,
            functionCalldata: hex"b4b46434",
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });

        input[0] = data;

        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // ETH/rswETH
        asset = 0xFAe103DC9cf190eD75350761e95403b7b8aFa6c0;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0xFAe103DC9cf190eD75350761e95403b7b8aFa6c0,
            functionCalldata: hex"679aefce",
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });

        input[0] = data;

        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // ETH/pufETH
        asset = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0xD9A442856C234a39a81a089C06451EBAa4306a72,
            functionCalldata: abi.encodeWithSignature("previewRedeem(uint256)", 1_000_000_000_000_000_000),
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });

        input[0] = data;

        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // WBTC/swBTC (note: different base asset)
        address wbtcBase = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        asset = 0x8DB2350D78aBc13f5673A411D4700BCF87864dDE;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0x8DB2350D78aBc13f5673A411D4700BCF87864dDE,
            functionCalldata: hex"99530b06",
            minRate: 100_000_000,
            maxRate: 100_000_000
        });

        input[0] = data;

        rateProvider.setRateProviderData(ERC20(wbtcBase), ERC20(asset), input);

        // ETH/apxETH
        asset = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6,
            functionCalldata: hex"35d16e17",
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });

        input[0] = data;

        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // ETH/sfrxETH
        asset = 0xac3E018457B222d93114458476f3E3416Abbe38F;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0xac3E018457B222d93114458476f3E3416Abbe38F,
            functionCalldata: hex"99530b06",
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });

        input[0] = data;

        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);
    }
}
