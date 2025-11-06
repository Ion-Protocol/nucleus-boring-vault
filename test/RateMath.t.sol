// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

contract RateMath is Test {

    using FixedPointMathLib for uint256;

    uint256 constant ACCEPTED_DELTA_PERCENT_OUT_OF_FAVOR = 0.000015e18;
    uint256 constant ACCEPTED_DELTA_PERCENT_IN_FAVOR = 0.01e18;

    // keep some state variables that each test can change according to the scenario it's testing
    uint256 ONE_SHARE;

    // exchange rate as reported in base decimals
    uint256 exchangeRateInBase;
    // base asset decimals, ALSO the exchange rate decimals
    uint256 baseDecimals;
    // the quote asset decimals
    uint256 quoteDecimals;
    // decimals returned by rate provider in base per quote
    uint256 quoteRateDecimals;
    // quote rate returned by rate provider
    uint256 quoteRate;

    function boundValues(
        uint256 depositAmount,
        uint256 startQuoteRate,
        uint256 startExchangeRate
    )
        internal
        returns (uint256 _depositAmount, uint256 _quoteRate, uint256 _exchangeRate)
    {
        // Bound Deposit 1 - 100,000,000 QuoteDecimals
        _depositAmount = bound(depositAmount, 1 * e(quoteDecimals), 100_000_000 * e(quoteDecimals));
        // Bound quote rate to 0.01 - 10 QuoteRateDecimals
        _quoteRate = bound(startQuoteRate, 1 * e(quoteRateDecimals - 2), 10 * e(quoteRateDecimals));
        // bound exchange rate to 0.8 - 2 baseDecimals
        _exchangeRate = bound(startExchangeRate, 8 * e(baseDecimals - 1), 2 * e(baseDecimals));
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
        ONE_SHARE = 10 ** baseDecimals;

        // bound values with helper function
        (depositAmount, quoteRate, exchangeRateInBase) = boundValues(depositAmount, startQuoteRate, startExchangeRate);

        // get shares out if deposit done
        uint256 shares = depositAssetForShares(depositAmount);

        // get assets back if all shares are withdrawn immediately
        uint256 assetsBack = withdrawSharesForAssets(shares);
        assertTrue(assetsBack <= depositAmount, "Users should never get back more assets than they deposited");
        assertApproxEqAbs(
            assetsBack,
            depositAmount,
            depositAmount.mulDivDown(ACCEPTED_DELTA_PERCENT_IN_FAVOR, 1e18),
            "assetsBack != depositAmount when atomic | In Favor"
        );
    }

    function testDepositAndWithdrawWithExchangeRateChange_18_6_Decimals(
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
        quoteRateDecimals = 6;
        ONE_SHARE = 10 ** baseDecimals;

        // bound values
        (depositAmount, startQuoteRate, startExchangeRate) =
            boundValues(depositAmount, startQuoteRate, startExchangeRate);
        exchangeRateInBase = startExchangeRate;
        quoteRate = startQuoteRate;
        rateChange = bound(rateChange, 9980, 10_020);

        // get shares out if deposit done
        uint256 shares = depositAssetForShares(depositAmount);

        // update the rate according to rate change
        exchangeRateInBase = exchangeRateInBase.mulDivDown(rateChange, 10_000);

        uint256 assetsBack = withdrawSharesForAssets(shares);
        // get expected amount out
        uint256 expected = (depositAmount * exchangeRateInBase * startQuoteRate) / (quoteRate * startExchangeRate);

        if (assetsBack > expected) {
            assertApproxEqAbs(
                assetsBack,
                expected,
                expected.mulDivDown(ACCEPTED_DELTA_PERCENT_OUT_OF_FAVOR, 1e18),
                "assetsBack != depositAmount with rate change | Out Of Favor"
            );
        }
        assertApproxEqAbs(
            assetsBack,
            expected,
            expected.mulDivDown(ACCEPTED_DELTA_PERCENT_IN_FAVOR, 1e18),
            "assetsBack != depositAmount with rate change | In Favor"
        );
    }

    function testDepositAndWithdrawWithQuoteRateChange_18_6_Decimals(
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
        quoteRateDecimals = 6;
        ONE_SHARE = 10 ** baseDecimals;

        // bound values
        (depositAmount, startQuoteRate, startExchangeRate) =
            boundValues(depositAmount, startQuoteRate, startExchangeRate);
        exchangeRateInBase = startExchangeRate;
        quoteRate = startQuoteRate;
        rateChange = bound(rateChange, 9980, 10_020);

        // get shares out if deposit done
        uint256 shares = depositAssetForShares(depositAmount);

        // update the rate according to rate change
        quoteRate = quoteRate.mulDivDown(rateChange, 10_000);

        uint256 assetsBack = withdrawSharesForAssets(shares);

        // get expected amount out
        uint256 expected = (depositAmount * exchangeRateInBase * startQuoteRate) / (quoteRate * startExchangeRate);

        if (assetsBack > expected) {
            assertApproxEqAbs(
                assetsBack,
                expected,
                expected.mulDivDown(ACCEPTED_DELTA_PERCENT_OUT_OF_FAVOR, 1e18),
                "assetsBack != depositAmount with rate change | Out Of Favor"
            );
        }
        assertApproxEqAbs(
            assetsBack,
            expected,
            expected.mulDivDown(ACCEPTED_DELTA_PERCENT_IN_FAVOR, 1e18),
            "assetsBack != depositAmount with rate change | In Favor"
        );
    }

    function testDepositAndWithdrawWithAllFuzzed_18_decimals(
        uint256 depositAmount,
        uint256 startQuoteRate,
        uint256 startExchangeRate,
        uint256 exchangeRateChange,
        uint256 quoteRateChange
    )
        external
    {
        // set decimals
        baseDecimals = 18;
        quoteDecimals = 18;
        quoteRateDecimals = quoteDecimals;
        ONE_SHARE = 10 ** baseDecimals;

        // bound values
        (depositAmount, startQuoteRate, startExchangeRate) =
            boundValues(depositAmount, startQuoteRate, startExchangeRate);
        exchangeRateInBase = startExchangeRate;
        quoteRate = startQuoteRate;
        exchangeRateChange = bound(exchangeRateChange, 5980, 20_020);
        quoteRateChange = bound(quoteRateChange, 5980, 20_020);

        // get shares out if deposit done
        uint256 shares = depositAssetForShares(depositAmount);

        // update the rate according to rate change
        exchangeRateInBase = exchangeRateInBase.mulDivDown(exchangeRateChange, 10_000);
        quoteRate = quoteRate.mulDivDown(quoteRateChange, 10_000);

        uint256 expected = (depositAmount * exchangeRateInBase * startQuoteRate) / (quoteRate * startExchangeRate);

        uint256 assetsBack = withdrawSharesForAssets(shares);

        if (assetsBack > expected) {
            assertApproxEqAbs(
                assetsBack,
                expected,
                expected.mulDivDown(ACCEPTED_DELTA_PERCENT_OUT_OF_FAVOR, 1e18),
                "assetsBack != depositAmount with rate change | Out Of Favor"
            );
        }
        assertApproxEqAbs(
            assetsBack,
            expected,
            expected.mulDivDown(ACCEPTED_DELTA_PERCENT_IN_FAVOR, 1e18),
            "assetsBack != depositAmount with rate change | In Favor"
        );
    }

    function testDepositAndWithdrawWithAllFuzzed_18_6_decimals(
        uint256 depositAmount,
        uint256 startQuoteRate,
        uint256 startExchangeRate,
        uint256 exchangeRateChange,
        uint256 quoteRateChange
    )
        external
    {
        // set decimals
        baseDecimals = 18;
        quoteDecimals = 6;
        quoteRateDecimals = quoteDecimals;
        ONE_SHARE = 10 ** baseDecimals;

        // bound values
        (depositAmount, startQuoteRate, startExchangeRate) =
            boundValues(depositAmount, startQuoteRate, startExchangeRate);
        exchangeRateInBase = startExchangeRate;
        quoteRate = startQuoteRate;
        exchangeRateChange = bound(exchangeRateChange, 5980, 20_020);
        quoteRateChange = bound(quoteRateChange, 5980, 20_020);

        // get shares out if deposit done
        uint256 shares = depositAssetForShares(depositAmount);

        // update the rate according to rate change
        exchangeRateInBase = exchangeRateInBase.mulDivDown(exchangeRateChange, 10_000);
        quoteRate = quoteRate.mulDivDown(quoteRateChange, 10_000);

        uint256 expected = (depositAmount * exchangeRateInBase * startQuoteRate) / (quoteRate * startExchangeRate);

        uint256 assetsBack = withdrawSharesForAssets(shares);

        if (assetsBack > expected) {
            assertApproxEqAbs(
                assetsBack,
                expected,
                expected.mulDivDown(ACCEPTED_DELTA_PERCENT_OUT_OF_FAVOR, 1e18),
                "assetsBack != depositAmount with rate change | Out Of Favor"
            );
        }
        assertApproxEqAbs(
            assetsBack,
            expected,
            expected.mulDivDown(ACCEPTED_DELTA_PERCENT_IN_FAVOR, 1e18),
            "assetsBack != depositAmount with rate change | In Favor"
        );
    }

    function withdrawSharesForAssets(uint256 shareAmount) public view returns (uint256 assetsOut) {
        assetsOut = shareAmount.mulDivDown(getRateInQuote(), ONE_SHARE);
    }

    function depositAssetForShares(uint256 depositAmount) public view returns (uint256 shares) {
        if (depositAmount == 0) revert("depositAssetForShares amount = 0");
        shares = depositAmount.mulDivDown(ONE_SHARE, getRateInQuote());
    }

    function getRateInQuote() public view returns (uint256 rateInQuote) {
        uint256 exchangeRateInQuoteDecimals = changeDecimals(exchangeRateInBase, baseDecimals, quoteDecimals);
        uint256 oneQuote = 10 ** quoteDecimals;
        rateInQuote = oneQuote.mulDivDown((exchangeRateInQuoteDecimals), quoteRate);
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

    /// @dev Helper function to perform 10**x
    function e(uint256 decimals) internal pure returns (uint256) {
        return (10 ** decimals);
    }

}
