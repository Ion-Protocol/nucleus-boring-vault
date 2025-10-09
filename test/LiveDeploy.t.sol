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
import { CrossChainTellerBase, BridgeData, ERC20 } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { MultiChainLayerZeroTellerWithMultiAssetSupport } from
    "src/base/Roles/CrossChain/MultiChainLayerZeroTellerWithMultiAssetSupport.sol";

import { console2 } from "forge-std/console2.sol";

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

contract LiveDeploy is ForkTest, DeployAll {
    using Strings for address;
    using StdJson for string;
    using FixedPointMathLib for uint256;

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

        // Warp to avoid minimum update delay post accountant deploy. This
        // wouldn't work if there were multiple _updateRate calls in a test.
        vm.warp(block.timestamp + 4000);
    }

    function testDepositAndBridge(uint256 amount) public {
        string memory tellerName = mainConfig.tellerContractName;
        if (compareStrings(tellerName, "MultiChainLayerZeroTellerWithMultiAssetSupport")) {
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
        deal(mainConfig.base, mainConfig.boringVault, depositAmount);

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
        vm.warp(accountant.getLastUpdateTimestamp()); // _updateRate warps to future for bypassing minmum update delay,
            // so we need to catch up
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

        depositAmount = bound(depositAmount, 0.5e18, 10_000e18);

        // mint a bunch of extra tokens to the vault for if rate increased
        deal(mainConfig.base, mainConfig.boringVault, depositAmount);
        uint256 expectedShares;
        uint256[] memory expectedSharesByAsset = new uint256[](assetsCount);
        uint256[] memory depositRateBefore = new uint256[](assetsCount);
        for (uint256 i; i < assetsCount; ++i) {
            depositRateBefore[i] = accountant.getDepositRate(ERC20(mainConfig.assets[i]));

            expectedSharesByAsset[i] = accountant.getSharesForDepositAmount(ERC20(mainConfig.assets[i]), depositAmount);
            expectedShares += expectedSharesByAsset[i];
            _depositAssetWithApprove(ERC20(mainConfig.assets[i]), depositAmount);
        }

        BoringVault boringVault = BoringVault(payable(mainConfig.boringVault));
        assertEq(boringVault.balanceOf(address(this)), expectedShares, "Should have received expected shares");

        // update the rate
        _updateRate(rateChange, accountant);

        // The deposit rate should have changed
        for (uint256 i; i < assetsCount; ++i) {
            assertApproxEqAbs(
                accountant.getDepositRate(ERC20(mainConfig.assets[i])),
                depositRateBefore[i] * 10_000 / rateChange,
                1,
                "Rate change did not apply to asset"
            );

            // mint extra assets for vault to give out
            deal(mainConfig.assets[i], mainConfig.boringVault, depositAmount * 2);

            uint256 expectedAssetsBack = ((depositAmount) * rateChange / 10_000);

            uint256 assetsOut = accountant.getAssetsOutForShares(ERC20(mainConfig.assets[i]), expectedSharesByAsset[i]);

            // Delta must be set very high to pass
            assertApproxEqAbs(assetsOut, expectedAssetsBack, DELTA, "assets out not equal to expected assets back");

            TellerWithMultiAssetSupport(mainConfig.teller).bulkWithdraw(
                ERC20(mainConfig.assets[i]), expectedSharesByAsset[i], expectedAssetsBack * 99 / 100, address(this)
            );

            assertApproxEqAbs(
                ERC20(mainConfig.assets[i]).balanceOf(address(this)),
                expectedAssetsBack,
                DELTA,
                "Should have been able to withdraw back the depositAmounts"
            );
        }
    }

    function testDepositASupportedAsset(uint256 depositAmount, uint256 indexOfSupported) public {
        uint256 assetsCount = mainConfig.assets.length;
        indexOfSupported = bound(indexOfSupported, 0, assetsCount);
        depositAmount = bound(depositAmount, 1, 10_000e18);

        uint256 expectedShares;
        AccountantWithRateProviders accountant = AccountantWithRateProviders(mainConfig.accountant);
        uint256[] memory expectedSharesByAsset = new uint256[](assetsCount);
        for (uint256 i; i < assetsCount; ++i) {
            expectedSharesByAsset[i] = accountant.getSharesForDepositAmount(ERC20(mainConfig.assets[i]), depositAmount);
            expectedShares += expectedSharesByAsset[i];

            _depositAssetWithApprove(ERC20(mainConfig.assets[i]), depositAmount);
        }

        BoringVault boringVault = BoringVault(payable(mainConfig.boringVault));
        assertEq(boringVault.balanceOf(address(this)), expectedShares, "Should have received expected shares");

        // withdrawal the assets for the same amount back
        for (uint256 i; i < assetsCount; ++i) {
            TellerWithMultiAssetSupport(mainConfig.teller).bulkWithdraw(
                ERC20(mainConfig.assets[i]), expectedSharesByAsset[i], depositAmount - 1, address(this)
            );
            assertApproxEqAbs(
                ERC20(mainConfig.assets[i]).balanceOf(address(this)),
                depositAmount,
                1,
                "Should have been able to withdraw back the depositAmounts"
            );
        }
    }

    function testAssetsAreAllNormalERC20(uint256 mintAmount, uint256 transferAmount) public {
        mintAmount = bound(mintAmount, 1, type(uint256).max);
        transferAmount = bound(transferAmount, 1, mintAmount);
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        for (uint256 i; i < mainConfig.assets.length; ++i) {
            ERC20 asset = ERC20(mainConfig.assets[i]);
            deal(address(asset), user1, mintAmount);
            assertEq(asset.balanceOf(user1), mintAmount, "asset did not deal to user1 correctly");
            uint256 totalSupplyStart = asset.totalSupply();
            vm.prank(user1);
            asset.transfer(user2, transferAmount);
            assertEq(asset.balanceOf(user1), mintAmount - transferAmount, "user1 balance not removed after transfer");
            assertEq(asset.balanceOf(user2), transferAmount, "user2 balance not incremented after transfer");
        }
    }

    function _depositAssetWithApprove(ERC20 asset, uint256 depositAmount) internal {
        deal(address(asset), address(this), depositAmount);
        asset.approve(mainConfig.boringVault, depositAmount);
        TellerWithMultiAssetSupport(mainConfig.teller).deposit(asset, depositAmount, 0, address(this));
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
        deal(address(asset), user, amount);

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
            refundRecipient: user,
            data: ""
        });

        uint256 ONE_SHARE = 10 ** boringVault.decimals();

        // so you don't really need to know exact shares in reality
        // just need to pass in a number roughly the same size to get quote
        // I still get the real number here for testing
        uint256 shares = accountant.getSharesForDepositAmount(asset, amount);
        uint256 quote = sourceTeller.previewFee(shares, data);
        uint256 assetBefore = asset.balanceOf(address(boringVault));

        sourceTeller.depositAndBridge{ value: quote }(asset, amount, shares, data);
        // verifyPackets(uint32(mainConfig.peerEid), addressToBytes32(address(mainConfig.teller)));

        assertEq(boringVault.balanceOf(user), 0, "Should have burned shares.");

        // assertEq(boringVault.balanceOf(userChain2), shares), ;

        assertEq(asset.balanceOf(address(boringVault)), assetBefore + shares, "boring vault should have shares");
        vm.stopPrank();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function _updateRate(uint96 rateChange, AccountantWithRateProviders accountant) internal {
        // update the rate
        // warp forward the minimumUpdateDelay for the accountant to prevent it from pausing on update test
        vm.startPrank(mainConfig.exchangeRateBot);
        uint96 newRate = uint96(accountant.getRate()) * rateChange / 10_000;
        accountant.updateExchangeRate(newRate);
        vm.stopPrank();
    }
}
