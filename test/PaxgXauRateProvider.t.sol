// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test } from "@forge-std/Test.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { PaxgXauRateProvider } from "src/oracles/PaxgXauRateProvider.sol";
import { IPriceFeed } from "src/interfaces/IPriceFeed.sol";

/**
 * @notice Minimal ERC20 used only to expose a configurable `decimals()` at construction.
 */
contract MockToken is ERC20 {

    constructor(uint8 decimals_) ERC20("PAX Gold", "PAXG", decimals_) { }

}

/**
 * @notice Minimal configurable Chainlink-style price feed used to drive the composite oracle
 * deterministically, without relying on a live fork or RPC.
 */
contract MockPriceFeed is IPriceFeed {

    uint8 internal _decimals;
    string internal _description;
    int256 internal _answer;
    uint256 internal _updatedAt;

    constructor(uint8 decimals_, string memory description_, int256 answer_, uint256 updatedAt_) {
        _decimals = decimals_;
        _description = description_;
        _answer = answer_;
        _updatedAt = updatedAt_;
    }

    function setAnswer(int256 answer_) external {
        _answer = answer_;
    }

    function setUpdatedAt(uint256 updatedAt_) external {
        _updatedAt = updatedAt_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, _answer, 0, _updatedAt, 0);
    }

    function getDataFeedId() external pure returns (bytes32) {
        return bytes32(0);
    }

}

contract PaxgXauRateProviderTest is Test {

    uint8 internal constant FEED_DECIMALS = 8;
    uint8 internal constant RATE_DECIMALS = 18;
    uint256 internal constant MAX_STALE = 1 days;

    // A recent, non-zero timestamp so freshness math is meaningful.
    uint256 internal constant NOW = 1_753_000_000;

    MockPriceFeed internal paxgUsdFeed;
    MockPriceFeed internal xauUsdFeed;
    MockToken internal paxgToken;
    PaxgXauRateProvider internal rateProvider;

    function setUp() external {
        vm.warp(NOW);

        // PAXG/USD ~ $3390, XAU/USD ~ $3400 (both 8-decimal Chainlink feeds).
        paxgUsdFeed = new MockPriceFeed(FEED_DECIMALS, "PAXG / USD", int256(3390e8), NOW);
        xauUsdFeed = new MockPriceFeed(FEED_DECIMALS, "XAU / USD", int256(3400e8), NOW);
        // PAXG is an 18-decimal token; the oracle reads RATE_DECIMALS from it at construction.
        paxgToken = new MockToken(RATE_DECIMALS);

        rateProvider = _deploy();
    }

    function _deploy() internal returns (PaxgXauRateProvider) {
        return new PaxgXauRateProvider(
            "PAXG / USD",
            "XAU / USD",
            ERC20(address(paxgToken)),
            IPriceFeed(address(paxgUsdFeed)),
            IPriceFeed(address(xauUsdFeed)),
            MAX_STALE
        );
    }

    /// @notice getRate returns XAU per PAXG scaled to 18 decimals.
    function testGetRate() external {
        uint256 rate = rateProvider.getRate();
        // rate = paxg(8) * 10^18 / xau(8) = 3390e8 * 1e18 / 3400e8
        uint256 expected = uint256(3390e8) * (10 ** RATE_DECIMALS) / uint256(3400e8);
        assertEq(rate, expected);
        // Sanity: PAXG ($3390) trades below one ounce of gold ($3400), so it is worth slightly
        // less than 1 XAU here, ~0.99706e18.
        assertLt(rate, 10 ** RATE_DECIMALS);
    }

    /// @notice Output precision is exactly 18 decimals (PAXG token decimals).
    function testRateDecimalsIs18() external view {
        assertEq(rateProvider.RATE_DECIMALS(), 18);
    }

    /// @notice RATE_DECIMALS is read from the PAXG token at construction, not hardcoded.
    function testRateDecimalsFollowsToken() external {
        MockToken sixDecimalToken = new MockToken(6);
        PaxgXauRateProvider provider = new PaxgXauRateProvider(
            "PAXG / USD",
            "XAU / USD",
            ERC20(address(sixDecimalToken)),
            IPriceFeed(address(paxgUsdFeed)),
            IPriceFeed(address(xauUsdFeed)),
            MAX_STALE
        );
        assertEq(provider.RATE_DECIMALS(), 6);
        // rate = paxg(8) * 10^6 / xau(8)
        assertEq(provider.getRate(), uint256(3390e8) * (10 ** 6) / uint256(3400e8));
    }

    /// @notice When both feeds report the same USD price, the rate is exactly 1e18.
    function testGetRateIsOneWhenPricesEqual() external {
        paxgUsdFeed.setAnswer(int256(3395e8));
        xauUsdFeed.setAnswer(int256(3395e8));
        assertEq(rateProvider.getRate(), 10 ** RATE_DECIMALS);
    }

    /// @notice A stale XAU feed reverts.
    function testStaleXauFeedReverts() external {
        xauUsdFeed.setUpdatedAt(NOW - MAX_STALE - 1);
        vm.expectRevert(
            abi.encodeWithSelector(PaxgXauRateProvider.MaxTimeFromLastUpdatePassed.selector, NOW, NOW - MAX_STALE - 1)
        );
        rateProvider.getRate();
    }

    /// @notice A stale PAXG feed reverts (checked after the XAU feed).
    function testStalePaxgFeedReverts() external {
        paxgUsdFeed.setUpdatedAt(NOW - MAX_STALE - 1);
        vm.expectRevert(
            abi.encodeWithSelector(PaxgXauRateProvider.MaxTimeFromLastUpdatePassed.selector, NOW, NOW - MAX_STALE - 1)
        );
        rateProvider.getRate();
    }

    /// @notice A feed at exactly the staleness boundary is still accepted.
    function testFeedAtStalenessBoundaryOk() external {
        xauUsdFeed.setUpdatedAt(NOW - MAX_STALE);
        paxgUsdFeed.setUpdatedAt(NOW - MAX_STALE);
        rateProvider.getRate();
    }

    /// @notice A negative XAU answer is rejected as invalid price data.
    function testNegativeXauAnswerReverts() external {
        xauUsdFeed.setAnswer(-1);
        vm.expectRevert(abi.encodeWithSelector(PaxgXauRateProvider.InvalidPrice.selector, int256(-1)));
        rateProvider.getRate();
    }

    /// @notice A zero XAU answer is rejected as invalid price data (would otherwise divide by zero).
    function testZeroXauAnswerReverts() external {
        xauUsdFeed.setAnswer(0);
        vm.expectRevert(abi.encodeWithSelector(PaxgXauRateProvider.InvalidPrice.selector, int256(0)));
        rateProvider.getRate();
    }

    /// @notice A negative PAXG answer is rejected as invalid price data.
    function testNegativePaxgAnswerReverts() external {
        paxgUsdFeed.setAnswer(-1);
        vm.expectRevert(abi.encodeWithSelector(PaxgXauRateProvider.InvalidPrice.selector, int256(-1)));
        rateProvider.getRate();
    }

    /// @notice A zero PAXG answer is rejected as invalid price data (would otherwise silently zero the rate).
    function testZeroPaxgAnswerReverts() external {
        paxgUsdFeed.setAnswer(0);
        vm.expectRevert(abi.encodeWithSelector(PaxgXauRateProvider.InvalidPrice.selector, int256(0)));
        rateProvider.getRate();
    }

    /// @notice Constructor rejects a PAXG feed whose description does not match.
    function testConstructorRejectsWrongPaxgDescription() external {
        MockPriceFeed badFeed = new MockPriceFeed(FEED_DECIMALS, "WRONG / USD", int256(3390e8), NOW);
        vm.expectRevert(PaxgXauRateProvider.InvalidDescription.selector);
        new PaxgXauRateProvider(
            "PAXG / USD",
            "XAU / USD",
            ERC20(address(paxgToken)),
            IPriceFeed(address(badFeed)),
            IPriceFeed(address(xauUsdFeed)),
            MAX_STALE
        );
    }

    /// @notice Constructor rejects an XAU feed whose description does not match.
    function testConstructorRejectsWrongXauDescription() external {
        MockPriceFeed badFeed = new MockPriceFeed(FEED_DECIMALS, "WRONG / USD", int256(3400e8), NOW);
        vm.expectRevert(PaxgXauRateProvider.InvalidDescription.selector);
        new PaxgXauRateProvider(
            "PAXG / USD",
            "XAU / USD",
            ERC20(address(paxgToken)),
            IPriceFeed(address(paxgUsdFeed)),
            IPriceFeed(address(badFeed)),
            MAX_STALE
        );
    }

    /// @notice Constructor rejects a feed that does not report 8 decimals.
    function testConstructorRejectsWrongDecimals() external {
        MockPriceFeed badFeed = new MockPriceFeed(18, "PAXG / USD", int256(3390e8), NOW);
        vm.expectRevert(abi.encodeWithSelector(PaxgXauRateProvider.InvalidPriceFeedDecimals.selector, uint8(18)));
        new PaxgXauRateProvider(
            "PAXG / USD",
            "XAU / USD",
            ERC20(address(paxgToken)),
            IPriceFeed(address(badFeed)),
            IPriceFeed(address(xauUsdFeed)),
            MAX_STALE
        );
    }

    /// @notice getRate() equals the intended formula (and stays overflow-free) across the realistic range.
    function testFuzzGetRate(uint256 xau, uint256 paxg) external {
        // Constrain to realistic 8-decimal USD prices in [$1, $1,000,000] to avoid overflow/zero.
        xau = bound(xau, 1e8, 1_000_000e8);
        paxg = bound(paxg, 1e8, 1_000_000e8);
        xauUsdFeed.setAnswer(int256(xau));
        paxgUsdFeed.setAnswer(int256(paxg));

        uint256 expected = paxg * (10 ** RATE_DECIMALS) / xau;
        assertEq(rateProvider.getRate(), expected);
    }

    /// @notice The rate scales monotonically with the PAXG/XAU price ratio: raising PAXG/USD never lowers the
    /// rate, and raising XAU/USD never raises it. Non-strict (>=/<=) because integer division can leave the
    /// rate unchanged across a small price move.
    function testFuzzGetRateMonotonic(uint256 xau, uint256 paxg, uint256 bump) external {
        // Leave headroom below the max so the bumped prices stay within the realistic range.
        xau = bound(xau, 1e8, 500_000e8);
        paxg = bound(paxg, 1e8, 500_000e8);
        bump = bound(bump, 1, 500_000e8);

        xauUsdFeed.setAnswer(int256(xau));
        paxgUsdFeed.setAnswer(int256(paxg));
        uint256 base = rateProvider.getRate();

        // Raising PAXG/USD (numerator) must not decrease the rate.
        paxgUsdFeed.setAnswer(int256(paxg + bump));
        assertGe(rateProvider.getRate(), base, "higher PAXG lowered rate");

        // Raising XAU/USD (denominator), with PAXG restored, must not increase the rate.
        paxgUsdFeed.setAnswer(int256(paxg));
        xauUsdFeed.setAnswer(int256(xau + bump));
        assertLe(rateProvider.getRate(), base, "higher XAU raised rate");
    }

}
