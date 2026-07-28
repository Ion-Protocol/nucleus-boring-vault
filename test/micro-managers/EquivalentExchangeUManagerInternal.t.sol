// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "@forge-std/Test.sol";
import { EquivalentExchangeUManager } from "src/micro-managers/EquivalentExchangeUManager.sol";

/// @notice Exposes EquivalentExchangeUManager's internal pure valuation helpers for direct testing.
contract EquivalentExchangeUManagerExternal is EquivalentExchangeUManager {

    // The UManager constructor only stores the manager/boringVault addresses and wires up Auth,
    // none of which the pure valuation helpers depend on, so dummy addresses are sufficient.
    constructor() EquivalentExchangeUManager(address(this), address(this), address(this)) { }

    function valueInUsd(uint256 balance, uint8 decimals, uint256 rate) external pure returns (uint256) {
        return _valueInUsd(balance, decimals, rate);
    }

    function usdValueToTokenAmount(uint256 usdValue, uint8 decimals, uint256 rate) external pure returns (uint256) {
        return _usdValueToTokenAmount(usdValue, decimals, rate);
    }

}

contract EquivalentExchangeUManagerInternal is Test {

    // One whole unit of normalized (USD) value, i.e. $1.00. Equal to the rate passed for a 1:1 USD asset.
    uint256 internal constant USD_RATE = 1e18;

    EquivalentExchangeUManagerExternal internal harness;

    function setUp() external {
        harness = new EquivalentExchangeUManagerExternal();
    }

    // ============================== _valueInUsd: USD assets (rate == NORMALIZED_ONE) ==============================

    // A USD asset is priced at rate == NORMALIZED_ONE, which reduces valuation to rescaling the balance to
    // 18 decimals.
    function test_ValueInUsd_UsdRateRescalesToEighteenDecimals() external view {
        assertEq(harness.valueInUsd(1_000_000, 6, USD_RATE), 1e18);
        assertEq(harness.valueInUsd(1, 6, USD_RATE), 1e12);
        assertEq(harness.valueInUsd(1e18, 18, USD_RATE), 1e18);
        assertEq(harness.valueInUsd(1, 18, USD_RATE), 1);
        assertEq(harness.valueInUsd(1e24, 24, USD_RATE), 1e18);
        // Balances not aligned to 10**(24-18) are truncated (floored) when rescaled down.
        assertEq(harness.valueInUsd(1_000_000_000_000_000_000_100_000, 24, USD_RATE), 1_000_000_000_000_000_000);
    }

    function test_ValueInUsd_ZeroBalanceIsZero() external view {
        assertEq(harness.valueInUsd(0, 6, USD_RATE), 0);
        assertEq(harness.valueInUsd(0, 8, 2000e18), 0);
    }

    // ============================== _valueInUsd: oracle-priced assets ==============================

    // A non-USD asset is priced by its oracle rate (USD per whole token, 18-dec).
    function test_ValueInUsd_PricesByRate() external view {
        // 1 whole 8-decimal token at $2000 -> $2000 of normalized value.
        assertEq(harness.valueInUsd(1e8, 8, 2000e18), 2000e18);
        // 3 whole 18-decimal tokens at $0.50 -> $1.50.
        assertEq(harness.valueInUsd(3e18, 18, 0.5e18), 1.5e18);
        // A $1 rate reproduces the USD-asset result.
        assertEq(harness.valueInUsd(1_000_000, 6, USD_RATE), 1e18);
    }

    // ============================== _usdValueToTokenAmount: USD assets (rate == NORMALIZED_ONE)
    // ==============================

    // A USD asset (rate == NORMALIZED_ONE) rescales the USD value back to native units, rounding up.
    function test_UsdValueToTokenAmount_UsdRateRescales() external view {
        assertEq(harness.usdValueToTokenAmount(1e18, 6, USD_RATE), 1_000_000);
        assertEq(harness.usdValueToTokenAmount(1e18, 18, USD_RATE), 1e18);
        assertEq(harness.usdValueToTokenAmount(1e18, 24, USD_RATE), 1e24);
        assertEq(harness.usdValueToTokenAmount(1, 24, USD_RATE), 1e6);
    }

    // A non-zero USD value that does not divide evenly into whole native units must round up so the subsidy
    // never underestimates what is owed.
    function test_UsdValueToTokenAmount_UsdRateRoundsUp() external view {
        // 1.5 units of a 6-decimal token (1.5e12 normalized) must round up to 2 native units.
        assertEq(harness.usdValueToTokenAmount(1_500_000_000_000, 6, USD_RATE), 2);
        // One wei above a whole unit rounds up to the next unit.
        assertEq(harness.usdValueToTokenAmount(1e12 + 1, 6, USD_RATE), 2);
        // Non-zero normalized amounts below one unit round up.
        assertEq(harness.usdValueToTokenAmount(999_999, 6, USD_RATE), 1);
        assertEq(harness.usdValueToTokenAmount(100_000, 6, USD_RATE), 1);
        assertEq(harness.usdValueToTokenAmount(1, 6, USD_RATE), 1);
    }

    // ============================== _usdValueToTokenAmount: oracle-priced assets ==============================

    // Converting USD to a non-USD token amount is the inverse of pricing, rounding up.
    function test_UsdValueToTokenAmount_ConvertsByRate() external view {
        // $2000 at $2000/token -> 1 whole 8-decimal token.
        assertEq(harness.usdValueToTokenAmount(2000e18, 8, 2000e18), 1e8);
        // $1.50 at $0.50/token -> 3 whole 18-decimal tokens.
        assertEq(harness.usdValueToTokenAmount(1.5e18, 18, 0.5e18), 3e18);
    }

    // Any USD value that does not divide evenly into whole native units must round up so the subsidy
    // never underestimates what is owed.
    function test_UsdValueToTokenAmount_RoundsUp() external view {
        // $1 at $3/token = 0.3333... tokens; an 18-dec token rounds the wei up.
        uint256 amount = harness.usdValueToTokenAmount(1e18, 18, 3e18);
        assertEq(amount, 333_333_333_333_333_334); // ceil(1e36 / 3e18)
        // Re-pricing the rounded-up amount must cover at least the input value.
        assertGe(harness.valueInUsd(amount, 18, 3e18), 1e18);
    }

    // ============================== round-trip property ==============================

    // Round-trip property the subsidy path relies on: converting a USD value to a token amount (round up)
    // then re-pricing it must never fall short of the original USD value, so the value invariant holds. The
    // rate range spans the USD asset (NORMALIZED_ONE) and sane oracle prices ($0.0001 .. $1,000,000).
    function testFuzz_UsdValueToTokenAmount_NeverUnderCovers(
        uint256 usdValue,
        uint8 decimals,
        uint256 rate
    )
        external
        view
    {
        decimals = uint8(bound(decimals, 0, 18));
        usdValue = bound(usdValue, 0, 1e30);
        rate = bound(rate, 1e14, 1e24);

        uint256 tokenAmount = harness.usdValueToTokenAmount(usdValue, decimals, rate);
        assertGe(harness.valueInUsd(tokenAmount, decimals, rate), usdValue);
    }

}
