// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "@forge-std/Test.sol";
import { EquivalentExchangeUManager } from "src/micro-managers/EquivalentExchangeUManager.sol";

/// @notice Exposes EquivalentExchangeUManager's internal pure valuation helpers for direct testing.
contract EquivalentExchangeUManagerExternal is EquivalentExchangeUManager {

    // The UManager constructor only stores the manager/boringVault addresses and wires up Auth,
    // none of which the pure valuation helpers depend on, so dummy addresses are sufficient.
    constructor() EquivalentExchangeUManager(address(this), address(this), address(this)) { }

    // Compose _unitRate with the value helpers exactly as the contract does, so the (decimals, rate) inputs
    // stay intuitive in tests while exercising the real per-unit-rate helpers. `rate` is an 18-decimal
    // price here, so its rateDecimals is NORMALIZED_DECIMALS.
    function referenceValue(uint256 balance, uint8 decimals, uint256 rate) external pure returns (uint256) {
        return _tokenAmountToReferenceValue(balance, _unitRate(rate, uint8(NORMALIZED_DECIMALS), decimals));
    }

    function referenceValueToTokenAmount(uint256 value, uint8 decimals, uint256 rate) external pure returns (uint256) {
        return _referenceValueToTokenAmount(value, _unitRate(rate, uint8(NORMALIZED_DECIMALS), decimals));
    }

    // Same as the pair above, but with an explicit `rateDecimals` so tests can drive `_unitRate` into its
    // divide branch (rateDecimals + tokenDecimals > 2 * NORMALIZED_DECIMALS), which the NORMALIZED_DECIMALS
    // rateDecimals used above can never reach.
    function unitRate(uint256 rate, uint8 rateDecimals, uint8 tokenDecimals) external pure returns (uint256) {
        return _unitRate(rate, rateDecimals, tokenDecimals);
    }

    function referenceValueWithRateDecimals(
        uint256 balance,
        uint8 tokenDecimals,
        uint256 rate,
        uint8 rateDecimals
    )
        external
        pure
        returns (uint256)
    {
        return _tokenAmountToReferenceValue(balance, _unitRate(rate, rateDecimals, tokenDecimals));
    }

    function referenceValueToTokenAmountWithRateDecimals(
        uint256 value,
        uint8 tokenDecimals,
        uint256 rate,
        uint8 rateDecimals
    )
        external
        pure
        returns (uint256)
    {
        return _referenceValueToTokenAmount(value, _unitRate(rate, rateDecimals, tokenDecimals));
    }

}

contract EquivalentExchangeUManagerInternal is Test {

    // Rate passed for a 1:1 token, i.e. one worth exactly one reference unit per whole token. Equal to
    // NORMALIZED_ONE (10**18).
    uint256 internal constant UNIT_RATE = 1e18;

    EquivalentExchangeUManagerExternal internal harness;

    function setUp() external {
        harness = new EquivalentExchangeUManagerExternal();
    }

    // ============================== _tokenAmountToReferenceValue: 1:1 tokens (rate == NORMALIZED_ONE)
    // ==============================

    // A 1:1 token is priced at rate == NORMALIZED_ONE, which reduces valuation to rescaling the balance to
    // 18 decimals.
    function test_ReferenceValue_UnitRateRescalesToEighteenDecimals() external view {
        assertEq(harness.referenceValue(1_000_000, 6, UNIT_RATE), 1e18);
        assertEq(harness.referenceValue(1, 6, UNIT_RATE), 1e12);
        assertEq(harness.referenceValue(1e18, 18, UNIT_RATE), 1e18);
        assertEq(harness.referenceValue(1, 18, UNIT_RATE), 1);
        assertEq(harness.referenceValue(1e24, 24, UNIT_RATE), 1e18);
        // Balances not aligned to 10**(24-18) are truncated (floored) when rescaled down.
        assertEq(harness.referenceValue(1_000_000_000_000_000_000_100_000, 24, UNIT_RATE), 1_000_000_000_000_000_000);
    }

    function test_ReferenceValue_ZeroBalanceIsZero() external view {
        assertEq(harness.referenceValue(0, 6, UNIT_RATE), 0);
        assertEq(harness.referenceValue(0, 8, 2000e18), 0);
    }

    // ============================== _tokenAmountToReferenceValue: oracle-priced tokens ==============================

    // A non-1:1 token is priced by its oracle rate (reference asset per whole token, 18-dec).
    function test_ReferenceValue_PricesByRate() external view {
        // 1 whole 8-decimal token at 2000 reference units -> 2000 units of value.
        assertEq(harness.referenceValue(1e8, 8, 2000e18), 2000e18);
        // 3 whole 18-decimal tokens at 0.50 reference units -> 1.50 units.
        assertEq(harness.referenceValue(3e18, 18, 0.5e18), 1.5e18);
        // A unit rate reproduces the 1:1-token result.
        assertEq(harness.referenceValue(1_000_000, 6, UNIT_RATE), 1e18);
    }

    // ============================== _referenceValueToTokenAmount: 1:1 tokens (rate == NORMALIZED_ONE)
    // ==============================

    // A 1:1 token (rate == NORMALIZED_ONE) rescales the value back to native units, rounding up.
    function test_ReferenceValueToTokenAmount_UnitRateRescales() external view {
        assertEq(harness.referenceValueToTokenAmount(1e18, 6, UNIT_RATE), 1_000_000);
        assertEq(harness.referenceValueToTokenAmount(1e18, 18, UNIT_RATE), 1e18);
        assertEq(harness.referenceValueToTokenAmount(1e18, 24, UNIT_RATE), 1e24);
        assertEq(harness.referenceValueToTokenAmount(1, 24, UNIT_RATE), 1e6);
    }

    // A non-zero value that does not divide evenly into whole native units must round up so the subsidy
    // never underestimates what is owed.
    function test_ReferenceValueToTokenAmount_UnitRateRoundsUp() external view {
        // 1.5 units of a 6-decimal token (1.5e12 normalized) must round up to 2 native units.
        assertEq(harness.referenceValueToTokenAmount(1_500_000_000_000, 6, UNIT_RATE), 2);
        // One wei above a whole unit rounds up to the next unit.
        assertEq(harness.referenceValueToTokenAmount(1e12 + 1, 6, UNIT_RATE), 2);
        // Non-zero normalized amounts below one unit round up.
        assertEq(harness.referenceValueToTokenAmount(999_999, 6, UNIT_RATE), 1);
        assertEq(harness.referenceValueToTokenAmount(100_000, 6, UNIT_RATE), 1);
        assertEq(harness.referenceValueToTokenAmount(1, 6, UNIT_RATE), 1);
    }

    // ============================== _referenceValueToTokenAmount: oracle-priced tokens ==============================

    // Converting a value to a non-1:1 token amount is the inverse of pricing, rounding up.
    function test_ReferenceValueToTokenAmount_ConvertsByRate() external view {
        // 2000 reference units at 2000/token -> 1 whole 8-decimal token.
        assertEq(harness.referenceValueToTokenAmount(2000e18, 8, 2000e18), 1e8);
        // 1.50 reference units at 0.50/token -> 3 whole 18-decimal tokens.
        assertEq(harness.referenceValueToTokenAmount(1.5e18, 18, 0.5e18), 3e18);
    }

    // Any value that does not divide evenly into whole native units must round up so the subsidy
    // never underestimates what is owed.
    function test_ReferenceValueToTokenAmount_RoundsUp() external view {
        // 1 reference unit at 3/token = 0.3333... tokens; an 18-dec token rounds the wei up.
        uint256 amount = harness.referenceValueToTokenAmount(1e18, 18, 3e18);
        assertEq(amount, 333_333_333_333_333_334); // ceil(1e36 / 3e18)
        // Re-pricing the rounded-up amount must cover at least the input value.
        assertGe(harness.referenceValue(amount, 18, 3e18), 1e18);
    }

    // ============================== round-trip property ==============================

    // Round-trip property the subsidy path relies on: converting a value to a token amount (round up) then
    // re-pricing it must never fall short of the original value, so the value invariant holds. The rate
    // range spans the 1:1 token (NORMALIZED_ONE) and sane oracle prices (0.0001 .. 1,000,000 reference units).
    function testFuzz_ReferenceValueToTokenAmount_NeverUnderCovers(
        uint256 value,
        uint8 decimals,
        uint256 rate
    )
        external
        view
    {
        decimals = uint8(bound(decimals, 0, 18));
        value = bound(value, 0, 1e30);
        rate = bound(rate, 1e14, 1e24);

        uint256 tokenAmount = harness.referenceValueToTokenAmount(value, decimals, rate);
        assertGe(harness.referenceValue(tokenAmount, decimals, rate), value);
    }

    // Same property, but forcing `_unitRate` into its divide branch. The fuzz above fixes rateDecimals at
    // NORMALIZED_DECIMALS (18) and caps tokenDecimals at 18, so shrink = 18 + decimals <= 36 = grow always
    // holds and only the lossless multiply branch runs. Here both decimals are >= 19, so
    // shrink >= 38 > 36 and `_unitRate` divides (and floors). The divide is lossy, but as long as the unit
    // rate stays nonzero the round-up in `_referenceValueToTokenAmount` still makes the round trip cover the
    // input. A zero unit rate is the separate boundary asserted below.
    function testFuzz_ReferenceValueToTokenAmount_NeverUnderCovers_DivideBranch(
        uint256 value,
        uint8 tokenDecimals,
        uint8 rateDecimals,
        uint256 rate
    )
        external
        view
    {
        tokenDecimals = uint8(bound(tokenDecimals, 19, 30));
        rateDecimals = uint8(bound(rateDecimals, 19, 30));
        // Net right-shift `_unitRate` applies: unitRate = rate / 10**e. e >= 2 here (both decimals >= 19).
        uint256 e = uint256(rateDecimals) + tokenDecimals - (2 * 18);
        // Keep the unit rate nonzero (rate >= 10**e) so the conversion is defined and the property is
        // meaningful; the zero-unit-rate case reverts and is covered by the dedicated test below.
        rate = bound(rate, 10 ** e, (10 ** e) * 1e18);
        value = bound(value, 0, 1e30);

        uint256 tokenAmount =
            harness.referenceValueToTokenAmountWithRateDecimals(value, tokenDecimals, rate, rateDecimals);
        assertGe(harness.referenceValueWithRateDecimals(tokenAmount, tokenDecimals, rate, rateDecimals), value);
    }

    // Boundary behind the `_unitRate` finding: an extreme (rateDecimals + tokenDecimals) shrinks a nonzero
    // oracle rate all the way to a zero unit rate. Converting any nonzero value against a zero unit rate then
    // reverts on division by zero rather than silently under-covering, so the subsidy path fails closed.
    function test_UnitRate_FloorsToZero_ConversionReverts() external {
        // shrink = 72, grow = 36, so unitRate = rate / 10**36. 1e18 / 1e36 floors to 0.
        assertEq(harness.unitRate(1e18, 36, 36), 0);

        vm.expectRevert();
        harness.referenceValueToTokenAmountWithRateDecimals(1e18, 36, 1e18, 36);
    }

}
