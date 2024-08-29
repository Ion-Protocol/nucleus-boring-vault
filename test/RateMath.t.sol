// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

contract RateMath is Test {
    using FixedPointMathLib for uint256;

    uint256 ONE_SHARE;
    uint256 exchangeRateInBase;
    uint256 baseDecimals;
    uint256 quoteDecimals;
    uint256 quoteRateDecimals;
    uint256 quoteRate;

    function setUp() external {
        // hard coded at 18 since in deploy script vault is set to 18 decimals, and this is set to that
        ONE_SHARE = 1e18;
    }

    function testAtomicDepositAndWithdraw_18Decimals(
        uint256 depositAmount,
        uint256 startQuoteRate,
        uint256 startExchangeRate
    )
        external
    {
        // set decimals
        baseDecimals = 18;
        quoteDecimals = 18;
        quoteRateDecimals = 18;

        // bound values
        depositAmount = bound(depositAmount, 1, 100_000_000e18);
        quoteRate = bound(startQuoteRate, 1e18, 10_000e18);
        exchangeRateInBase = bound(startExchangeRate, 8e17, 2e18);

        // get shares out if deposit done
        uint256 shares = depositAssetForShares(depositAmount);

        // get assets back if all shares are withdrawn immediatelly
        uint256 assetsBack = withdrawSharesForAssets(shares);

        assertFalse(assetsBack > depositAmount, "The assets back should not be > deposit amount when atomic");
        assertApproxEqAbs(assetsBack, depositAmount, 2, "assetsBack != depositAmount when atomic");
    }

    function testDepositAndWithdrawWithRateChange_18Decimals(
        uint256 depositAmount,
        uint256 startQuoteRate,
        uint256 startExchangeRate,
        uint256 rateChange
    )
        external
    {
        // set decimals
        baseDecimals = 18;
        quoteDecimals = 18;
        quoteRateDecimals = 18;

        // bound values
        depositAmount = bound(depositAmount, 1, 100_000_000e18);
        quoteRate = bound(startQuoteRate, 1e18, 10_000e18);
        exchangeRateInBase = bound(startExchangeRate, 8e17, 2e18);
        rateChange = bound(rateChange, 9980, 10_020);

        // get shares out if deposit done
        uint256 shares = depositAssetForShares(depositAmount);

        // update the rate according to rate change
        exchangeRateInBase = exchangeRateInBase.mulDivDown(rateChange, 10_000);

        // get assets back if all shares are withdrawn immediatelly
        uint256 assetsBack = withdrawSharesForAssets(shares);

        if (assetsBack > depositAmount) {
            console.log("Problem. assets back should not be > deposit amount");
            console.log("AssetsBack: ", assetsBack);
            console.log("DepositAmount: ", depositAmount);
            console.log("Difference: ", assetsBack - depositAmount);
        }
        assertFalse(assetsBack > depositAmount, "The assets back should not be > deposit amount");
        assertApproxEqAbs(assetsBack, depositAmount, 2, "assetsBack != depositAmount with rate change");
    }

    function testDepositAndWithdrawWithRateChange_18Decimals_Quote6(
        uint256 depositAmount,
        uint256 startQuoteRate,
        uint256 startExchangeRate,
        uint256 rateChange
    )
        external
    {
        // set decimals
        baseDecimals = 18;
        quoteDecimals = 6;
        quoteRateDecimals = 18;

        // bound values
        depositAmount = bound(depositAmount, 1, 100_000_000e6);
        quoteRate = bound(startQuoteRate, 1e18, 10_000e18);
        exchangeRateInBase = bound(startExchangeRate, 8e17, 2e18);
        rateChange = bound(rateChange, 9980, 10_020);

        // get shares out if deposit done
        uint256 shares = depositAssetForShares(depositAmount);

        // update the rate according to rate change
        exchangeRateInBase = exchangeRateInBase.mulDivDown(rateChange, 10_000);

        // get assets back if all shares are withdrawn immediatelly
        uint256 assetsBack = withdrawSharesForAssets(shares);

        if (assetsBack > depositAmount) {
            console.log("Problem. assets back should not be > deposit amount");
            console.log("AssetsBack: ", assetsBack);
            console.log("DepositAmount: ", depositAmount);
            console.log("Difference: ", assetsBack - depositAmount);
        }
        assertFalse(assetsBack > depositAmount, "The assets back should not be > deposit amount");
        //assertApproxEqAbs(assetsBack, depositAmount, 2, "assetsBack != depositAmount with rate change");
    }

    // function testMath(uint256 depositAmount, uint256 rateChange) external {
    //     depositAmount = bound(depositAmount, 1, 1_000_000_000e18);
    //     rateChange = bound(rateChange, 9998, 10_002);
    //     // get the expected assets back after rate change
    //     uint256 expectedAssetsBack = ((depositAmount).mulDivDown(rateChange, 10_000));

    //     // get the shares back when depositing before rate change
    //     uint accountantRateBefore = accountant.getRateInQuoteSafe(ERC20(WEETH));
    //     assertNotEq(accountantRateBefore, 1e18, "accountantRateBefore for WEETH equal to 1");
    //     uint256 depositShares = depositAmount.mulDivDown(ONE_SHARE, accountantRateBefore);
    //     console.log("Shares * Rate:\t\t", depositShares * ONE_SHARE);
    //     console.log("accountantRateBefore:\t\t", accountantRateBefore);

    //     // todo- atomic
    //     // change the rate
    //     uint96 newRate = uint96(accountant.getRate().mulDivDown(uint96(rateChange), 10_000));
    //     vm.warp(1 days + block.timestamp);
    //     accountant.updateExchangeRate(newRate);

    //     // calculate the assets out at the new rate
    //     uint accountantRateAfter = accountant.getRateInQuoteSafe(ERC20(WEETH));
    //     assertApproxEqAbs(accountantRateBefore.mulDivDown(rateChange, 10_000), accountantRateAfter, 1,
    // "accountantRateBefore not equal to after with rate applied");
    //     console.log("Shares * Rate:\t", depositShares * accountantRateAfter);
    //     console.log("one_share:\t\t", ONE_SHARE);
    //     uint256 assetsOut = depositShares.mulDivDown(accountantRateAfter, (ONE_SHARE));

    //     // print if the expected > out and assert they're the same
    //     console.log("expectedAssetsBack >= realAssetsOut: ", expectedAssetsBack >= assetsOut);
    //     console.log("expectedAssetsBack: ", expectedAssetsBack);
    //     console.log("assetsOut: ", assetsOut);
    //     // assertTrue(expectedAssetsBack >= assetsOut, "BIG PROBLEM, not in protocol's favor");
    //     assertApproxEqAbs(expectedAssetsBack, assetsOut, 1, "deposit * rateChange != depositAmount with");
    //     // getRateInQuoteSafe math");
    // }

    function withdrawSharesForAssets(uint256 shareAmount) public returns (uint256 assetsOut) {
        assetsOut = shareAmount.mulDivDown(getRateInQuote(), ONE_SHARE);
    }

    function depositAssetForShares(uint256 depositAmount) public returns (uint256 shares) {
        if (depositAmount == 0) revert("depositAssetForShares amount = 0");
        shares = depositAmount.mulDivDown(ONE_SHARE, getRateInQuote());
        // if (shares < minimumMint) revert (");
    }

    function getRateInQuote() public view returns (uint256 rateInQuote) {
        uint256 exchangeRateInQuoteDecimals = changeDecimals(exchangeRateInBase, baseDecimals, quoteDecimals);

        uint256 oneQuote = 10 ** quoteDecimals;
        rateInQuote = oneQuote.mulDivDown((exchangeRateInQuoteDecimals), quoteRate);
        // console.log("Quote Rate: ",quoteRate);
        // console.log("One Quote: ", oneQuote);
        // console.log("Exchange Rate In Quote Decimals: ", exchangeRateInQuoteDecimals);
    }

    function changeDecimals(uint256 amount, uint256 fromDecimals, uint256 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals < toDecimals) {
            return amount * 10 ** (toDecimals - fromDecimals);
        } else {
            return amount / 10 ** (fromDecimals - toDecimals);
        }
    }
}