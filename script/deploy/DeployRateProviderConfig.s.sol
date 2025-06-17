// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { RateProviderConfig } from "./../../../src/base/Roles/RateProviderConfig.sol";
import { BaseScript } from "../Base.s.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

using StdJson for string;

contract DeployRateProviderConfig is BaseScript {
    RateProviderConfig rateProvider;

    // deployer:            0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f00
    bytes32 constant SALT = 0x12341eD9cb38Ae1b15016c6eD9F88e247f2AF76f00fcdbd6afdd472179b79b16;
    address multisig;

    function run() public broadcast {
        string memory chainConfig = getChainConfigFile();
        multisig = chainConfig.readAddress(".multisig");

        require(multisig != address(0), "Multisig must not be set to 0 address");
        vm.prompt(
            string.concat(
                "You are about to deploy a Rate Provider Config on\nchainID ",
                vm.toString(block.chainid),
                "\nowner being set to: ",
                vm.toString(multisig),
                "\nThe rate provider data will be set according to the defaults defined in this file for this chain. In the future the multisig must update these configurations",
                "\nPlease double check these values and press ENTER to continue"
            )
        );

        bytes memory creationCode = type(RateProviderConfig).creationCode;

        rateProvider =
            RateProviderConfig(CREATEX.deployCreate3(SALT, abi.encodePacked(creationCode, abi.encode(broadcaster))));

        if (block.chainid == 1) {
            _configETH();
        } else if (block.chainid == 1329) {
            _configSEI();
        } else if (block.chainid == 999) {
            _configHYPERLIQUID();
        } else if (block.chainid == 98_866) {
            _configPLUME();
        }

        rateProvider.transferOwnership(multisig);
        require(rateProvider.owner() == multisig, "Owner not the multisig");
        console.log("deployed to: ", address(rateProvider));
    }

    /*
    * DEFAULT CONFIGS FOR EACH CHAIN
    */
    function _configETH() internal {
        // BASE ASSET WETH
        address base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        RateProviderConfig.RateProviderData[] memory input = new RateProviderConfig.RateProviderData[](1);
        RateProviderConfig.RateProviderData memory data;
        address asset;

        // stETH/wstETH
        // Base: WETH | Quote: wstETH
        asset = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            functionCalldata: hex"035faf82",
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_400_000_000_000_000_000
        });
        // New rate provider info:
        // rateProvider: 0xF7c9C121b09cd45591554EB8419A4e8a47E7b0a8
        // functionCalldata: hex"679aefce"
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        //eeETH/weETH
        // Base: WETH | Quote: WEETH
        asset = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee,
            functionCalldata: abi.encodeWithSignature("getEETHByWeETH(uint256)", 1_000_000_000_000_000_000),
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });
        // New rate provider info:
        // rateProvider: 0x7d3B0CE57842b01aBf6C490646fBb694DFA389E4
        // functionCalldata: hex"679aefce"
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // ETH/ezETH
        // Base: WETH | ezETH
        asset = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0x3239396B740cD6BBABb42196A03f7B77fA7102C9,
            functionCalldata: hex"f13597a6",
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });
        // New rate provider info:
        // rateProvider: 0x0852BE00fA37fc24Fb34111E3a4e44A28FB76106
        // functionCalldata: hex"679aefce"
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // ETH/rsETH
        // Base: WETH | Quote: rsETH
        asset = 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0x349A73444b1a310BAe67ef67973022020d70020d,
            functionCalldata: hex"b4b46434",
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });
        // New rate provider info:
        // rateProvider: 0x6aeea90872fcFB5A45beFD070ADc3fCD8e71c067
        // functionCalldata: hex"679aefce"
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // ETH/rswETH
        // Base: WETH | Quote: rswETH
        asset = 0xFAe103DC9cf190eD75350761e95403b7b8aFa6c0;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0xFAe103DC9cf190eD75350761e95403b7b8aFa6c0,
            functionCalldata: hex"679aefce",
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });
        // New rate provider info:
        // rateProvider: 0x99554bBCb88C2A26897e77686EE5425cebfB4f01
        // functionCalldata: hex"679aefce"
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // ETH/pufETH
        // Base: WETH | Quote: pufETH
        asset = 0xD9A442856C234a39a81a089C06451EBAa4306a72;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0xD9A442856C234a39a81a089C06451EBAa4306a72,
            functionCalldata: abi.encodeWithSignature("previewRedeem(uint256)", 1_000_000_000_000_000_000),
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });
        // New rate provider info:
        // rateProvider: 0xBDa3CfA3BE083f4087cb3b647Da8dfCa51bDAa6A
        // functionCalldata: hex"679aefce"
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // WBTC/swBTC
        // Base: WBTC | Quote: swBTC
        address wbtcBase = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        asset = 0x8DB2350D78aBc13f5673A411D4700BCF87864dDE;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0x8DB2350D78aBc13f5673A411D4700BCF87864dDE,
            functionCalldata: hex"99530b06",
            minRate: 100_000_000,
            maxRate: 100_000_000
        });
        // New rate provider info:
        // rateProvider: 0x318Da095d602C08eF41319f4c4bA0646d318C906
        // functionCalldata: hex"679aefce"
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(wbtcBase), ERC20(asset), input);

        // ETH/apxETH
        // Base: WETH | Quote: apxETH
        asset = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6,
            functionCalldata: hex"35d16e17",
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });
        // New rate provider info:
        // rateProvider: 0x9a044a83Ddd7De8cAfd8ecbf70bf7dAD4865cF44
        // functionCalldata: hex"679aefce"
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // ETH/sfrxETH
        // Base: WETH | Quote: sfrxETH
        asset = 0xac3E018457B222d93114458476f3E3416Abbe38F;
        data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0xac3E018457B222d93114458476f3E3416Abbe38F,
            functionCalldata: hex"99530b06",
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_200_000_000_000_000_000
        });
        // New rate provider info:
        // rateProvider: 0xa427b23b686986ED993B4BA9Ae23Bf65022f938a
        // functionCalldata: hex"679aefce"
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // BASE ASSET USDC
        address usdcBase = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        asset = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        data = RateProviderConfig.RateProviderData(true, address(0), hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(usdcBase), ERC20(asset), input);

        asset = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
        data = RateProviderConfig.RateProviderData(true, address(0), hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(usdcBase), ERC20(asset), input);

        asset = 0x437cc33344a0B27A429f795ff6B469C72698B291;
        data = RateProviderConfig.RateProviderData(true, address(0), hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(usdcBase), ERC20(asset), input);

        asset = 0x59D9356E565Ab3A36dD77763Fc0d87fEaf85508C;
        data = RateProviderConfig.RateProviderData(true, address(0), hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(usdcBase), ERC20(asset), input);

        asset = 0x57F5E098CaD7A3D1Eed53991D4d66C45C9AF7812;
        data =
            RateProviderConfig.RateProviderData(false, 0xD5e8ea00c9d1aFD4f84A02Cff08203Cb2beC4478, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(usdcBase), ERC20(asset), input);

        asset = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
        data =
            RateProviderConfig.RateProviderData(false, 0x3D2021776e385601857E7b7649de955525E21d23, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(usdcBase), ERC20(asset), input);

        asset = 0x15700B564Ca08D9439C58cA5053166E8317aa138;
        data = RateProviderConfig.RateProviderData(true, address(0), hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(usdcBase), ERC20(asset), input);

        asset = 0xaf37c1167910ebC994e266949387d2c7C326b879;
        data = RateProviderConfig.RateProviderData(true, address(0), hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(usdcBase), ERC20(asset), input);

        asset = 0x96F6eF951840721AdBF46Ac996b59E0235CB985C;
        data =
            RateProviderConfig.RateProviderData(false, 0x78Fe29ef4192c9c88B9EA1E708aDB0572f6340B3, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(usdcBase), ERC20(asset), input);

        asset = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        data = RateProviderConfig.RateProviderData(true, address(0), hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(usdcBase), ERC20(asset), input);

        asset = 0xF469fBD2abcd6B9de8E169d128226C0Fc90a012e;
        data = RateProviderConfig.RateProviderData(true, address(0), hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(wbtcBase), ERC20(asset), input);

        asset = 0x18084fbA666a33d37592fA2633fD49a74DD93a88;
        data = RateProviderConfig.RateProviderData(true, address(0), hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(wbtcBase), ERC20(asset), input);

        asset = 0x8236a87084f8B84306f72007F36F2618A5634494;
        data = RateProviderConfig.RateProviderData(true, address(0), hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(wbtcBase), ERC20(asset), input);

        // BASE ASSET UNKNOWN
        address unknownBase = 0xFE6c47Fe352103Cab601C44769C7260b7eb3F81e;
        asset = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        data = RateProviderConfig.RateProviderData(true, address(0), hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(unknownBase), ERC20(asset), input);
    }

    function _configSEI() internal {
        address base = 0x160345fC359604fC6e70E3c5fAcbdE5F7A9342d8;

        // ETH/seiyanETH
        // Base: WETH | Quote: seiyanETH
        address asset = 0x9fAaEA2CDd810b21594E54309DC847842Ae301Ce;
        RateProviderConfig.RateProviderData memory data = RateProviderConfig.RateProviderData({
            isPeggedToBase: false,
            rateProvider: 0x24152894Decc7384b05E8907D6aDAdD82c176499,
            functionCalldata: hex"282a8700",
            minRate: 1_000_000_000_000_000_000,
            maxRate: 1_100_000_000_000_000_000
        });
        RateProviderConfig.RateProviderData[] memory input = new RateProviderConfig.RateProviderData[](1);
        input[0] = data;

        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);
    }

    function _configHYPERLIQUID() internal {
        RateProviderConfig.RateProviderData[] memory input = new RateProviderConfig.RateProviderData[](1);
        RateProviderConfig.RateProviderData memory data;

        // BASE ASSET WHYPE
        address base = 0x5555555555555555555555555555555555555555;

        address asset = 0x5748ae796AE46A4F1348a1693de4b50560485562;
        data =
            RateProviderConfig.RateProviderData(false, 0xcE621a3CA6F72706678cFF0572ae8d15e5F001c3, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        asset = 0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1;
        data =
            RateProviderConfig.RateProviderData(true, 0x000000000000000000000000000000000000dEaD, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        asset = 0x5748ae796AE46A4F1348a1693de4b50560485562;
        data =
            RateProviderConfig.RateProviderData(false, 0xcE621a3CA6F72706678cFF0572ae8d15e5F001c3, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);
    }

    function _configPLUME() internal {
        RateProviderConfig.RateProviderData[] memory input = new RateProviderConfig.RateProviderData[](1);
        RateProviderConfig.RateProviderData memory data;

        // BASE ASSET USDC
        address base = 0x54FD4da2Fa19Cf0f63d8f93A6EA5BEd3F9C042C6;

        address asset = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;
        data =
            RateProviderConfig.RateProviderData(false, 0xbB2fAA1e1D6183EE3c4177476ce0d70CBd55A388, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        asset = 0x78adD880A697070c1e765Ac44D65323a0DcCE913;
        data = RateProviderConfig.RateProviderData(false, address(0), hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // BASE ASSET USDC.e
        base = 0x78adD880A697070c1e765Ac44D65323a0DcCE913;

        asset = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;
        data =
            RateProviderConfig.RateProviderData(false, 0xbB2fAA1e1D6183EE3c4177476ce0d70CBd55A388, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        asset = 0x593cCcA4c4bf58b7526a4C164cEEf4003C6388db;
        data =
            RateProviderConfig.RateProviderData(false, 0xe0CF451d6E373FF04e8eE3c50340F18AFa6421E1, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        asset = 0x11113Ff3a60C2450F4b22515cB760417259eE94B;
        data =
            RateProviderConfig.RateProviderData(false, 0xa67d20A49e6Fe68Cf97E556DB6b2f5DE1dF4dC2f, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        asset = 0xdeA736937d464d288eC80138bcd1a2E109A200e3;
        data =
            RateProviderConfig.RateProviderData(false, 0x2f35AedE6662408a897642739c9BE999054a9F68, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        asset = 0xb52b090837a035f93A84487e5A7D3719C32Aa8A9;
        data =
            RateProviderConfig.RateProviderData(false, 0xB0D00195cE43F2708AAeBb9f6E37c202389019fC, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        asset = 0xE72Fe64840F4EF80E3Ec73a1c749491b5c938CB9;
        data =
            RateProviderConfig.RateProviderData(false, 0x0b738cd187872b265A689e8e4130C336e76892eC, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        // BASE ASSET pUSD
        base = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;

        asset = 0x11a8d8694b656112d9a94285223772F4aAd269fc;
        data = RateProviderConfig.RateProviderData(false, address(0), hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);

        asset = 0x593cCcA4c4bf58b7526a4C164cEEf4003C6388db;
        data =
            RateProviderConfig.RateProviderData(false, 0xe0CF451d6E373FF04e8eE3c50340F18AFa6421E1, hex"679aefce", 0, 0);
        input[0] = data;
        rateProvider.setRateProviderData(ERC20(base), ERC20(asset), input);
    }
}
