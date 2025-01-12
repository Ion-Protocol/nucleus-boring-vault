// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";
import { DeployAll } from "script/deploy/deployAll.s.sol";
import { ConfigReader } from "script/ConfigReader.s.sol";
import { SOLVER_ROLE } from "script/deploy/single/06_DeployRolesAuthority.s.sol";
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
import { CrossChainTellerBase, BridgeData } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { CrossChainOPTellerWithMultiAssetSupport } from
    "src/base/Roles/CrossChain/CrossChainOPTellerWithMultiAssetSupport.sol";
import { MultiChainLayerZeroTellerWithMultiAssetSupport } from
    "src/base/Roles/CrossChain/MultiChainLayerZeroTellerWithMultiAssetSupport.sol";

// import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { console2 } from "forge-std/console2.sol";

string constant DEFAULT_RPC_URL = "L1_RPC_URL";
uint256 constant DELTA = 10_000;

interface IUSDM {
    function mint(address to, uint256 amount) external;
    function owner() external view returns (address);
}

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

contract LiveDeploy is ForkTest, DeployAll {
    using Strings for address;
    using StdJson for string;
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

    ERC20 constant NATIVE_ERC20 = ERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    uint256 ONE_SHARE;

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

        runLiveTest(FILE_NAME);

        // check for if all rate providers are deployed, if not error
        for (uint256 i; i < mainConfig.assets.length; ++i) {
            // set the corresponding rate provider
            string memory isPeggedKey = string(
                abi.encodePacked(".assetToRateProviderAndPriceFeed.", mainConfig.assets[i].toHexString(), ".isPegged")
            );

            bool isPegged = getChainConfigFile().readBool(isPeggedKey);

            if (!isPegged) {
                string memory key = string(
                    abi.encodePacked(
                        ".assetToRateProviderAndPriceFeed.", mainConfig.assets[i].toHexString(), ".rateProvider"
                    )
                );

                address rateProvider = getChainConfigFile().readAddress(key);
                assertNotEq(rateProvider, address(0), "Rate provider address is 0");
                assertNotEq(rateProvider.code.length, 0, "No code at rate provider address");
            }
        }

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

    function testDepositAndBridge(uint256 amount) public {
        string memory tellerName = mainConfig.tellerContractName;
        if (compareStrings(tellerName, "CrossChainOPTellerWithMultiAssetSupport")) {
            _testOPDepositAndBridge(ERC20(mainConfig.base), amount);
        } else if (compareStrings(tellerName, "MultiChainLayerZeroTellerWithMultiAssetSupport")) {
            _testLZDepositAndBridge(ERC20(mainConfig.base), amount);
        } else { }
    }

    function testDepositBaseAssetAndUpdateRate(uint256 depositAmount, uint256 rateChange256) public {
        AccountantWithRateProviders accountant = AccountantWithRateProviders(mainConfig.accountant);
        // bound and cast since bound does not support uint96
        uint96 rateChange = uint96(
            bound(rateChange256, mainConfig.allowedExchangeRateChangeLower, mainConfig.allowedExchangeRateChangeUpper)
        );

        depositAmount = bound(depositAmount, 1, 10_000e18);

        // mint a bunch of extra tokens to the vault for if rate increased
        _deal(mainConfig.base, mainConfig.boringVault, depositAmount);

        _depositAssetWithApprove(ERC20(mainConfig.base), depositAmount);
        BoringVault boringVault = BoringVault(payable(mainConfig.boringVault));
        uint256 expected_shares = depositAmount;

        assertEq(
            boringVault.balanceOf(address(this)),
            expected_shares,
            "Should have received expected shares 1:1 for base asset"
        );

        // update the rate
        _updateRate(rateChange, accountant);

        uint256 expectedAssetsBack = depositAmount * rateChange / 10_000;

        // attempt a withdrawal after
        TellerWithMultiAssetSupport(mainConfig.teller).bulkWithdraw(
            ERC20(mainConfig.base), expected_shares, expectedAssetsBack, address(this)
        );
        assertEq(
            ERC20(mainConfig.base).balanceOf(address(this)),
            expectedAssetsBack,
            "Should have been able to withdraw back the depositAmount with rate factored"
        );
    }

    function testDepositBaseAssetOnStartingRate(uint256 depositAmount, uint256 rateChange256) public {
        AccountantWithRateProviders accountant = AccountantWithRateProviders(mainConfig.accountant);

        // bound and cast since bound does not support uint96
        uint96 rateChange = uint96(
            bound(rateChange256, mainConfig.allowedExchangeRateChangeLower, mainConfig.allowedExchangeRateChangeUpper)
        );
        depositAmount = bound(depositAmount, 2, 10_000e18);

        // update the rate
        _updateRate(rateChange, accountant);
        _depositAssetWithApprove(ERC20(mainConfig.base), depositAmount);

        BoringVault boringVault = BoringVault(payable(mainConfig.boringVault));
        uint256 sharesOut = boringVault.balanceOf(address(this));

        // attempt a withdrawal after
        TellerWithMultiAssetSupport(mainConfig.teller).bulkWithdraw(
            ERC20(mainConfig.base), sharesOut, depositAmount - 2, address(this)
        );

        assertApproxEqAbs(
            ERC20(mainConfig.base).balanceOf(address(this)),
            depositAmount,
            2,
            "Should have been able to withdraw back the depositAmount"
        );
    }

    function testDepositBaseAsset(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, 10_000e18);
        _depositAssetWithApprove(ERC20(mainConfig.base), depositAmount);

        BoringVault boringVault = BoringVault(payable(mainConfig.boringVault));
        uint256 expected_shares = depositAmount;
        assertEq(
            boringVault.balanceOf(address(this)),
            expected_shares,
            "Should have received expected shares 1:1 for base asset"
        );

        // attempt a withdrawal after
        TellerWithMultiAssetSupport(mainConfig.teller).bulkWithdraw(
            ERC20(mainConfig.base), expected_shares, depositAmount, address(this)
        );
        assertEq(
            ERC20(mainConfig.base).balanceOf(address(this)),
            depositAmount,
            "Should have been able to withdraw back the depositAmount"
        );
    }

    function testDepositASupportedAssetAndUpdateRate(uint256 depositAmount, uint96 rateChange) public {
        uint256 assetsCount = mainConfig.assets.length;
        AccountantWithRateProviders accountant = AccountantWithRateProviders(mainConfig.accountant);
        // manual bounding done because bound() doesn't exist for uint96
        rateChange = rateChange % uint96(mainConfig.allowedExchangeRateChangeUpper - 1);
        rateChange = (rateChange < mainConfig.allowedExchangeRateChangeLower + 1)
            ? mainConfig.allowedExchangeRateChangeLower + 1
            : rateChange;

        depositAmount = bound(depositAmount, 1e6, 1_000_000e6);
        console2.log("depositAmount: ", depositAmount);

        uint256[] memory depositAmountLD = new uint256[](assetsCount);

        for (uint256 i; i < assetsCount; ++i) {
            // depositAmountLD[i] = depositAmount * 10 ** ERC20(mainConfig.assets[i]).decimals();
            uint256 quoteDecimals = ERC20(mainConfig.assets[i]).decimals();
            console2.log("10**quoteDecimals: ", 10 ** quoteDecimals);
            console2.log("ERC20(mainConfig.assets[i]).totalSupply(): ", ERC20(mainConfig.assets[i]).totalSupply());
            depositAmountLD[i] = bound(depositAmount, 10 ** quoteDecimals, ERC20(mainConfig.assets[i]).totalSupply());
        }

        // mint a bunch of extra tokens to the vault for if rate increased
        // _deal(mainConfig.base, mainConfig.boringVault, depositAmount);
        uint256 expecteShares;
        uint256[] memory expectedSharesByAsset = new uint256[](assetsCount);
        uint256[] memory rateInQuoteBefore = new uint256[](assetsCount);
        for (uint256 i; i < assetsCount; ++i) {
            rateInQuoteBefore[i] = accountant.getRateInQuoteSafe(ERC20(mainConfig.assets[i]));
            expectedSharesByAsset[i] =
                depositAmountLD[i].mulDivDown(ONE_SHARE, accountant.getRateInQuoteSafe(ERC20(mainConfig.assets[i])));
            expecteShares += expectedSharesByAsset[i];
            _depositAssetWithApprove(ERC20(mainConfig.assets[i]), depositAmountLD[i]);
        }

        BoringVault boringVault = BoringVault(payable(mainConfig.boringVault));
        assertEq(boringVault.balanceOf(address(this)), expecteShares, "Should have received expected shares");

        // update the rate
        _updateRate(rateChange, accountant);

        // withdrawal the assets for the same amount back
        for (uint256 i; i < assetsCount; ++i) {
            assertApproxEqAbs(
                accountant.getRateInQuote(ERC20(mainConfig.assets[i])),
                rateInQuoteBefore[i] * rateChange / 10_000,
                1,
                "Rate change did not apply to asset"
            );

            // mint extra assets for vault to give out
            _deal(mainConfig.assets[i], mainConfig.boringVault, depositAmountLD[i] * 2);

            uint256 expectedAssetsBack = ((depositAmountLD[i]) * rateChange / 10_000);

            console2.log("depositAmountLD[i]: ", depositAmountLD[i]);
            console2.log("expectedSharesByAsset[i]: ", expectedSharesByAsset[i]);
            uint256 assetsOut = expectedSharesByAsset[i].mulDivDown(
                accountant.getRateInQuoteSafe(ERC20(mainConfig.assets[i])), ONE_SHARE
            );

            // WARNING This is meant to fail if quote decimals is ever less than shares decimals.
            uint256 decimalsDiff = 10 ** (ERC20(mainConfig.assets[i]).decimals() - boringVault.decimals());
            assertApproxEqAbs(
                assetsOut, expectedAssetsBack, decimalsDiff * 2, "assets out not equal to expected assets back"
            );

            TellerWithMultiAssetSupport(mainConfig.teller).bulkWithdraw(
                ERC20(mainConfig.assets[i]), expectedSharesByAsset[i], expectedAssetsBack * 99 / 100, address(this)
            );

            assertApproxEqAbs(
                ERC20(mainConfig.assets[i]).balanceOf(address(this)),
                expectedAssetsBack,
                decimalsDiff * 2,
                "Should have been able to withdraw back the depositAmounts"
            );
        }
    }

    function testDepositASupportedAssetWithoutRateUpdate(uint256 depositAmount, uint256 indexOfSupported) public {
        uint256 assetsCount = mainConfig.assets.length;
        indexOfSupported = bound(indexOfSupported, 0, assetsCount);
        depositAmount = bound(depositAmount, 1, 10_000e6);

        uint256[] memory depositAmountLD = new uint256[](assetsCount);

        uint256 sharesDecimals = BoringVault(payable(mainConfig.boringVault)).decimals();
        for (uint256 i; i < assetsCount; ++i) {
            uint256 quoteDecimals = ERC20(mainConfig.assets[i]).decimals();

            // `getRateInQuote` loses precision if the quote decimal is less than the shares decimals
            require(quoteDecimals >= sharesDecimals, "quoteDecimals must be greater than or equal to sharesDecimals");

            // deposit = quoteDecimals * sharesDecimals / quoteDecimals
            // assuming internal rate calculation is precise, any deposit amount
            // in decimals < 1e(quoteDecimals - sharesDecimals) will truncate to zero
            // depositAmountLD[i] = bound(depositAmount, 10 ** (quoteDecimals - sharesDecimals), 10_000e18);
            depositAmountLD[i] =
                bound(depositAmount, 10 ** (quoteDecimals - sharesDecimals), ERC20(mainConfig.assets[i]).totalSupply());

            console2.log("depositAmountLD[i]: ", depositAmountLD[i]);
        }

        console2.log("after getting deposit amounts");

        uint256 expecteShares;
        AccountantWithRateProviders accountant = AccountantWithRateProviders(mainConfig.accountant);
        uint256[] memory expectedSharesByAsset = new uint256[](assetsCount);
        for (uint256 i; i < assetsCount; ++i) {
            expectedSharesByAsset[i] =
                depositAmountLD[i].mulDivDown(ONE_SHARE, accountant.getRateInQuoteSafe(ERC20(mainConfig.assets[i])));
            expecteShares += expectedSharesByAsset[i];

            _depositAssetWithApprove(ERC20(mainConfig.assets[i]), depositAmountLD[i]);
        }

        console2.log("after deposit assets");

        BoringVault boringVault = BoringVault(payable(mainConfig.boringVault));
        assertEq(boringVault.balanceOf(address(this)), expecteShares, "Should have received expected shares");

        // withdrawal the assets for the same amount back
        for (uint256 i; i < assetsCount; ++i) {
            // For minimum amount out, zero out the last number of digits equal to (quoteDecimals - sharesDecimals)
            uint256 decimalsDiff = 10 ** (ERC20(mainConfig.assets[i]).decimals() - sharesDecimals);

            console2.log("depositAmountLD[i]: ", depositAmountLD[i]);
            uint256 minimumAssetsOut = depositAmountLD[i] / decimalsDiff * decimalsDiff - decimalsDiff;

            uint256 rateInQuote = accountant.getRateInQuote(ERC20(mainConfig.assets[i]));
            console2.log("rateInQuote: ", rateInQuote);
            uint256 expectedReceive = expectedSharesByAsset[i] * rateInQuote / ONE_SHARE;
            console2.log("expectedReceive: ", expectedReceive);

            uint256 receiveAmountLD = TellerWithMultiAssetSupport(mainConfig.teller).bulkWithdraw(
                ERC20(mainConfig.assets[i]), expectedSharesByAsset[i], minimumAssetsOut, address(this)
            );
            assertApproxEqAbs(
                receiveAmountLD,
                depositAmountLD[i],
                decimalsDiff,
                "Should have been able to withdraw back the depositAmounts"
            );
        }
    }

    function testAssetsAreAllNormalERC20(uint256 mintAmount, uint256 transferAmount) public {
        mintAmount = bound(mintAmount, 1, 1_000_000e6);
        transferAmount = bound(transferAmount, 1, mintAmount);
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        for (uint256 i; i < mainConfig.assets.length; ++i) {
            ERC20 asset = ERC20(mainConfig.assets[i]);
            _deal(address(asset), user1, mintAmount);
            assertApproxEqAbs(asset.balanceOf(user1), mintAmount, 2, "asset did not deal to user1 correctly");
            uint256 totalSupplyStart = asset.totalSupply();
            vm.prank(user1);
            IERC20(address(asset)).safeTransfer(user2, transferAmount);
            assertApproxEqAbs(
                asset.balanceOf(user1), mintAmount - transferAmount, 2, "user1 balance not removed after transfer"
            );
            assertApproxEqAbs(asset.balanceOf(user2), transferAmount, 2, "user2 balance not incremented after transfer");
        }
    }

    function _depositAssetWithApprove(ERC20 asset, uint256 depositAmount) internal {
        console2.log("_depositAssetWithApprove");
        console2.log("address(asset): ", address(asset));
        console2.log("depositAmount: ", depositAmount);

        _deal(address(asset), address(this), depositAmount);
        console2.log("balance", asset.balanceOf(address(this)));
        // require(asset.balanceOf(address(this)) == depositAmount, "_depositAssetWithApprove deal failed");

        console2.log("after deal");
        uint256 allowance = asset.allowance(address(this), mainConfig.boringVault);
        console2.log("allowance: ", allowance);

        // Without `forceApprove`, just `approve` reverts in Foundry on USDT due
        // to having no return value and requiring the existing allowance to be
        // zero. Even if we enforce the existing allowance to be zero, foundry
        // was still throwing an EVM revert on USDT approve.
        IERC20(address(asset)).forceApprove(address(mainConfig.boringVault), depositAmount);
        console2.log("after approve");
        TellerWithMultiAssetSupport(mainConfig.teller).deposit(asset, depositAmount, 0);
    }

    function _testLZDepositAndBridge(ERC20 asset, uint256 amount) internal {
        MultiChainLayerZeroTellerWithMultiAssetSupport sourceTeller =
            MultiChainLayerZeroTellerWithMultiAssetSupport(mainConfig.teller);
        BoringVault boringVault = BoringVault(payable(mainConfig.boringVault));
        AccountantWithRateProviders accountant = AccountantWithRateProviders(mainConfig.accountant);

        amount = bound(amount, 0.0001e18, 10_000e18);
        // make a user and give them BASE
        address user = makeAddr("A user");
        address userChain2 = makeAddr("A user on chain 2");
        _deal(address(asset), user, amount);

        // approve teller to spend BASE
        vm.startPrank(user);
        vm.deal(user, 10e18);
        asset.approve(address(boringVault), amount);

        // perform depositAndBridge
        BridgeData memory data = BridgeData({
            chainSelector: mainConfig.peerEid,
            destinationChainReceiver: userChain2,
            bridgeFeeToken: NATIVE_ERC20,
            messageGas: 100_000,
            data: ""
        });

        uint256 ONE_SHARE = 10 ** boringVault.decimals();

        // so you don't really need to know exact shares in reality
        // just need to pass in a number roughly the same size to get quote
        // I still get the real number here for testing
        uint256 shares = amount.mulDivDown(ONE_SHARE, accountant.getRateInQuoteSafe(asset));
        uint256 quote = sourceTeller.previewFee(shares, data);
        uint256 assetBefore = asset.balanceOf(address(boringVault));

        sourceTeller.depositAndBridge{ value: quote }(asset, amount, shares, data);
        // verifyPackets(uint32(mainConfig.peerEid), addressToBytes32(address(mainConfig.teller)));

        assertEq(boringVault.balanceOf(user), 0, "Should have burned shares.");

        // assertEq(boringVault.balanceOf(userChain2), shares), ;

        assertEq(asset.balanceOf(address(boringVault)), assetBefore + shares, "boring vault should have shares");
        vm.stopPrank();
    }

    function _testOPDepositAndBridge(ERC20 asset, uint256 amount) internal {
        CrossChainOPTellerWithMultiAssetSupport sourceTeller =
            CrossChainOPTellerWithMultiAssetSupport(mainConfig.teller);
        BoringVault boringVault = BoringVault(payable(mainConfig.boringVault));
        AccountantWithRateProviders accountant = AccountantWithRateProviders(mainConfig.accountant);

        amount = bound(amount, 0.0001e18, 10_000e18);
        // make a user and give them BASE

        address user = makeAddr("A user");
        address userChain2 = makeAddr("A user on chain 2");
        _deal(address(asset), user, amount);

        // approve teller to spend BASE
        vm.startPrank(user);
        vm.deal(user, 10e18);
        asset.approve(mainConfig.boringVault, amount);

        // perform depositAndBridge
        BridgeData memory data = BridgeData({
            chainSelector: 0,
            destinationChainReceiver: userChain2,
            bridgeFeeToken: NATIVE_ERC20,
            messageGas: 100_000,
            data: ""
        });

        uint256 ONE_SHARE = 10 ** boringVault.decimals();

        uint256 shares = amount.mulDivDown(ONE_SHARE, accountant.getRateInQuoteSafe(asset));
        uint256 quote = 0;

        uint256 wethBefore = asset.balanceOf(address(boringVault));

        sourceTeller.depositAndBridge{ value: quote }(asset, amount, shares, data);

        assertEq(boringVault.balanceOf(user), 0, "Should have burned shares.");

        assertEq(asset.balanceOf(address(boringVault)), wethBefore + shares, "boring vault should have shares");
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function _updateRate(uint96 rateChange, AccountantWithRateProviders accountant) internal {
        // update the rate
        // warp forward the minimumUpdateDelay for the accountant to prevent it from pausing on update test
        uint256 time = block.timestamp;
        vm.warp(time + mainConfig.minimumUpdateDelayInSeconds);
        vm.startPrank(mainConfig.exchangeRateBot);
        uint96 newRate = uint96(accountant.getRate()) * rateChange / 10_000;
        accountant.updateExchangeRate(newRate);
        vm.stopPrank();
        vm.warp(time);
    }

    /**
     * Certain tokens such as rebasing tokens are not compatible with the
     * regular `deal`. For those, we can implement custom deal logic.
     */
    function _deal(address asset, address to, uint256 amount) internal returns (uint256) {
        ERC20 M_TOKEN = ERC20(0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b);
        ERC20 WM_TOKEN = ERC20(0x437cc33344a0B27A429f795ff6B469C72698B291);
        ERC20 USDM_TOKEN = ERC20(0x59D9356E565Ab3A36dD77763Fc0d87fEaf85508C);
        ERC20 RUSDY_TOKEN = ERC20(0xaf37c1167910ebC994e266949387d2c7C326b879);

        if (asset == address(M_TOKEN)) {
            address mHolder = 0x3f0376da3Ae4313E7a5F1dA184BAFC716252d759;
            vm.startPrank(mHolder);
            M_TOKEN.transfer(to, amount);
            vm.stopPrank();
        } else if (asset == address(WM_TOKEN)) {
            address wmHolder = 0x4Cbc25559DbBD1272EC5B64c7b5F48a2405e6470;
            vm.startPrank(wmHolder);
            WM_TOKEN.transfer(to, amount);
            vm.stopPrank();
        } else if (asset == 0x59D9356E565Ab3A36dD77763Fc0d87fEaf85508C) {
            console2.log("mint USDM");
            address usdmMinter = 0x4109f7E577596432458F8D4DC2E78637428D5614;
            vm.startPrank(usdmMinter);
            IUSDM(address(USDM_TOKEN)).mint(to, amount);
            vm.stopPrank();
            // address usdmHolder = 0xeF9A3cE48678D7e42296166865736899C3638B0E;
            // vm.startPrank(usdmHolder);
            // USDM_TOKEN.transfer(to, amount);
            // vm.stopPrank();
        } else if (asset == address(RUSDY_TOKEN)) {
            address rusdyHolder = 0xA18D2F95cfB492b65dBffad6216e3428e9d14362;
            vm.startPrank(rusdyHolder);
            RUSDY_TOKEN.transfer(to, amount);
            vm.stopPrank();
        } else {
            deal(asset, to, amount);
        }
        // require(ERC20(asset).balanceOf(to) == amount, "deal failed");
        return amount;
    }
}
