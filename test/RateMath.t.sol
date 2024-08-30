// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { Test, stdStorage, StdStorage, stdError, console } from "@forge-std/Test.sol";

contract RateMath is Test {
    using FixedPointMathLib for uint256;

    // basis points
    // accept 10% delta
    uint256 constant ACCEPTED_DELTA_PERCENT = 1;

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

    function setUp() external {
        // hard coded at 18 since in deploy script vault is set to 18 decimals, and this is set to that
        ONE_SHARE = 1e18;
    }

    // started on a helper function for bounds
    function boundValues(
        uint256 depositAmount,
        uint256 startQuoteRate,
        uint256 startExchangeRate
    )
        internal
        returns (uint256 _depositAmount, uint256 _quoteRate, uint256 _exchangeRate)
    {
        /// NOTE rounding error is problematic with very small deposits, so start at 1e4
        _depositAmount = bound(depositAmount, 1 * e(quoteDecimals), 100_000_000 * e(quoteDecimals));
        // base per quote
        _quoteRate = bound(startQuoteRate, 1 * e(quoteRateDecimals - 2), 10 * e(quoteRateDecimals));
        _exchangeRate = bound(startExchangeRate, 8 * e(baseDecimals - 1), 2 * e(baseDecimals));
    }

    /**
     * here's the real test
     * wbtc = 100,000 usdc on the dot, I have the quote rate from data provider return 10 do I get 1 share out if I
     * deposit 100,000 usdc? you should
     * now wbtc goes to 105,000 usdc, I withdraw one share and I should get 105,000 usdc...what do I actually get...
     */
    function testJamieBTCScenario(uint256 depositAmount) external {
        baseDecimals = 8;
        quoteDecimals = 6;
        quoteRateDecimals = 6;

        depositAmount = bound(depositAmount, 1 * e(quoteDecimals), 100_000_000 * e(quoteDecimals));
        // BASE PER QUOTE returning in quote decimals
        quoteRate = 10;
        exchangeRateInBase = 1 * e(baseDecimals);

        uint256 shares = depositAssetForShares(depositAmount);
        console.log("returned shares: ", shares);

        quoteRate = 9;

        uint256 assetsBack = withdrawSharesForAssets(shares);
        assertEq(assetsBack, 105_000 * e(quoteDecimals), "I withdraw one share and I should get 105,000 usdc");
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

        // bound values with helper function
        (depositAmount, quoteRate, exchangeRateInBase) = boundValues(depositAmount, startQuoteRate, startExchangeRate);

        // get shares out if deposit done
        uint256 shares = depositAssetForShares(depositAmount);

        // get assets back if all shares are withdrawn immediatelly
        uint256 assetsBack = withdrawSharesForAssets(shares);

        assertFalse(assetsBack > depositAmount, "The assets back should not be > deposit amount when atomic");
        assertApproxEqAbs(
            assetsBack,
            depositAmount,
            depositAmount.mulDivDown(ACCEPTED_DELTA_PERCENT, 10_000),
            "assetsBack != depositAmount when atomic"
        );
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
        (depositAmount, quoteRate, exchangeRateInBase) = boundValues(depositAmount, startQuoteRate, startExchangeRate);
        rateChange = bound(rateChange, 9980, 10_020);

        // get shares out if deposit done
        uint256 shares = depositAssetForShares(depositAmount);

        // update the rate according to rate change
        exchangeRateInBase = exchangeRateInBase.mulDivDown(rateChange, 10_000);

        // get assets back if all shares are withdrawn immediatelly
        uint256 assetsBack = withdrawSharesForAssets(shares);
        uint256 newDepositAmountValue = depositAmount.mulDivDown(rateChange, 10_000);

        if (assetsBack > newDepositAmountValue) {
            console.log("Problem. assets back should not be > deposit amount * rate change");
            console.log("AssetsBack: ", assetsBack);
            console.log("NewDepositAmount: ", newDepositAmountValue);
            console.log("Difference: ", assetsBack - newDepositAmountValue);
        }
        assertApproxEqAbs(
            assetsBack,
            newDepositAmountValue,
            newDepositAmountValue.mulDivDown(ACCEPTED_DELTA_PERCENT, 10_000),
            "assetsBack != depositAmount with rate change"
        );
        // assertFalse(assetsBack > newDepositAmountValue, "The assets back should not be > deposit amount * rate
        // change");
    }

    // WIP testing with 6 decimals, not yet using helper
    function testDepositAndWithdrawWithRateChange_6Decimals_Quote18(
        uint256 depositAmount,
        uint256 startQuoteRate,
        uint256 startExchangeRate,
        uint256 rateChange
    )
        external
    {
        // set decimals
        baseDecimals = 6;
        quoteDecimals = 18;
        quoteRateDecimals = 18;

        // bound values
        (depositAmount, quoteRate, exchangeRateInBase) = boundValues(depositAmount, startQuoteRate, startExchangeRate);
        rateChange = bound(rateChange, 9980, 10_020);

        // get shares out if deposit done
        uint256 shares = depositAssetForShares(depositAmount);

        // update the rate according to rate change
        exchangeRateInBase = exchangeRateInBase.mulDivDown(rateChange, 10_000);
        uint256 newDepositAmountValue = depositAmount.mulDivDown(rateChange, 10_000);

        // get assets back if all shares are withdrawn immediatelly
        uint256 assetsBack = withdrawSharesForAssets(shares);

        if (assetsBack > newDepositAmountValue) {
            console.log("Problem. assets back should not be > deposit amount * rate change");
            console.log("AssetsBack: ", assetsBack);
            console.log("NewDepositAmount: ", newDepositAmountValue);
            console.log("Difference: ", assetsBack - newDepositAmountValue);
        }
        assertApproxEqAbs(
            assetsBack,
            newDepositAmountValue,
            newDepositAmountValue.mulDivDown(ACCEPTED_DELTA_PERCENT, 10_000),
            "assetsBack != depositAmount with rate change"
        );
        // assertFalse(assetsBack > newDepositAmountValue, "The assets back should not be > deposit amount * rate
        // change");
    }

    function testDepositAndWithdrawWithRateChange_FuzzDecimals(
        uint256 depositAmount,
        uint256 startQuoteRate,
        uint256 startExchangeRate,
        uint256 rateChange,
        uint256 baseAssetDecimals,
        uint256 quoteAssetDecimals
    )
        external
    {
        // set decimals
        baseDecimals = bound(baseAssetDecimals, 6, 18);
        quoteDecimals = bound(baseAssetDecimals, 6, 18);
        quoteRateDecimals = quoteDecimals;

        // bound values
        (depositAmount, quoteRate, exchangeRateInBase) = boundValues(depositAmount, startQuoteRate, startExchangeRate);
        rateChange = bound(rateChange, 9980, 10_020);

        // get shares out if deposit done
        uint256 shares = depositAssetForShares(depositAmount);

        // update the rate according to rate change
        exchangeRateInBase = exchangeRateInBase.mulDivDown(rateChange, 10_000);
        uint256 newDepositAmountValue = depositAmount.mulDivDown(rateChange, 10_000);

        // get assets back if all shares are withdrawn immediatelly
        uint256 assetsBack = withdrawSharesForAssets(shares);

        if (assetsBack > newDepositAmountValue) {
            console.log("Problem. assets back should not be > deposit amount * rate change");
            console.log("AssetsBack: ", assetsBack);
            console.log("NewDepositAmount: ", newDepositAmountValue);
            console.log("Difference: ", assetsBack - newDepositAmountValue);
        }
        assertApproxEqAbs(
            assetsBack,
            newDepositAmountValue,
            newDepositAmountValue.mulDivDown(ACCEPTED_DELTA_PERCENT, 10_000),
            "assetsBack != depositAmount with rate change"
        );
        // assertFalse(assetsBack > newDepositAmountValue, "The assets back should not be > deposit amount * rate
        // change");
    }

    function withdrawSharesForAssets(uint256 shareAmount) public returns (uint256 assetsOut) {
        assetsOut = shareAmount.mulDivDown(getRateInQuote(), ONE_SHARE);
    }

    function depositAssetForShares(uint256 depositAmount) public returns (uint256 shares) {
        if (depositAmount == 0) revert("depositAssetForShares amount = 0");
        shares = depositAmount.mulDivDown(ONE_SHARE, getRateInQuote());
        // if (shares < minimumMint) revert (");
    }

    function getRateInQuote() public view returns (uint256 rateInQuote) {
        // exchangeRateInBase is called this because the rate provider will return decimals in that of base
        uint256 exchangeRateInQuoteDecimals = changeDecimals(exchangeRateInBase, baseDecimals, quoteDecimals);
        uint256 oneQuote = 10 ** quoteDecimals;
        rateInQuote = oneQuote.mulDivDown((exchangeRateInQuoteDecimals), quoteRate);
        console.log("Exchange Rate In Quote Decimals: ", exchangeRateInQuoteDecimals);
        console.log("Quote Rate: ", quoteRate);
        console.log("One Quote: ", oneQuote);
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

    function e(uint256 decimals) internal returns (uint256) {
        return (10 ** decimals);
    }
}
