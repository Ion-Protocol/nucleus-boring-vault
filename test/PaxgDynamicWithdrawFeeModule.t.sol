// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test } from "@forge-std/Test.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PaxgDynamicWithdrawFeeModule } from "src/helper/PaxgDynamicWithdrawFeeModule.sol";
import { PaxgXauRateProvider } from "src/oracles/PaxgXauRateProvider.sol";
import { IRateProvider } from "src/interfaces/IRateProvider.sol";
import { IPriceFeed } from "src/interfaces/IPriceFeed.sol";

/**
 * @notice Minimal ERC20 exposing a configurable `decimals()`; also stands in for the PAXG want token.
 */
contract MockToken is ERC20 {

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_, decimals_) { }

}

/**
 * @notice Minimal configurable Chainlink-style feed, matching the one used in the oracle's own tests.
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

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, _answer, 0, _updatedAt, 0);
    }

    function getDataFeedId() external pure returns (bytes32) {
        return bytes32(0);
    }

}

contract PaxgDynamicWithdrawFeeModuleTest is Test {

    uint8 internal constant FEED_DECIMALS = 8;
    uint256 internal constant PEG_PRICE = 1e18;
    uint256 internal constant MAX_STALE = 1 days;
    uint256 internal constant NOW = 1_753_000_000;

    MockPriceFeed internal paxgUsdFeed;
    MockPriceFeed internal xauUsdFeed;
    MockToken internal paxg;
    MockToken internal shares;
    PaxgXauRateProvider internal oracle;
    PaxgDynamicWithdrawFeeModule internal module;

    function setUp() external {
        vm.warp(NOW);

        paxgUsdFeed = new MockPriceFeed(FEED_DECIMALS, "PAXG / USD", int256(3400e8), NOW);
        xauUsdFeed = new MockPriceFeed(FEED_DECIMALS, "XAU / USD", int256(3400e8), NOW);
        paxg = new MockToken("PAX Gold", "PAXG", 18);
        shares = new MockToken("PAXGy", "PAXGy", 18);

        oracle = new PaxgXauRateProvider(
            "PAXG / USD",
            "XAU / USD",
            ERC20(address(paxg)),
            IPriceFeed(address(paxgUsdFeed)),
            IPriceFeed(address(xauUsdFeed)),
            MAX_STALE
        );

        module = new PaxgDynamicWithdrawFeeModule(IRateProvider(address(oracle)), IERC20(address(paxg)));
    }

    /// @dev Sets the PAXG:XAU market price by moving the PAXG/USD feed, holding XAU/USD at $3400.
    /// @param price PAXG:XAU price in 18-decimal fixed point (PEG_PRICE = 1.0).
    function _setPaxgXauPrice(uint256 price) internal {
        // p = paxgUsd / xauUsd  =>  paxgUsd = p * xauUsd
        paxgUsdFeed.setAnswer(int256(price * uint256(3400e8) / PEG_PRICE));
    }

    /// @dev offerAsset = shares, wantAsset = PAXG (the withdrawal target).
    function _fee(uint256 amount) internal view returns (uint256) {
        return module.calculateOfferFees(amount, IERC20(address(shares)), IERC20(address(paxg)), address(0xBEEF));
    }

    /// @dev Independent reference implementation of the fee (plain division + explicit round-up), used to
    /// cross-check the module's solmate mulDivUp without re-using its code path.
    function _expectedFee(uint256 amount, uint256 price) internal pure returns (uint256) {
        if (price <= PEG_PRICE) return 0;
        uint256 num = amount * (price - PEG_PRICE);
        uint256 f = num / price;
        if (num % price != 0) f++;
        return f;
    }

    function testConstructorRejectsZeroRateProvider() external {
        vm.expectRevert(PaxgDynamicWithdrawFeeModule.ZeroAddress.selector);
        new PaxgDynamicWithdrawFeeModule(IRateProvider(address(0)), IERC20(address(paxg)));
    }

    function testConstructorRejectsZeroPaxg() external {
        vm.expectRevert(PaxgDynamicWithdrawFeeModule.ZeroAddress.selector);
        new PaxgDynamicWithdrawFeeModule(IRateProvider(address(oracle)), IERC20(address(0)));
    }

    /// @notice PEG_PRICE must equal 10**(rate provider decimals); a mismatch would silently mis-scale fees.
    function testPegPriceMatchesRateProviderDecimals() external view {
        assertEq(module.PEG_PRICE(), 10 ** uint256(oracle.RATE_DECIMALS()));
    }

    /// @notice A non-PAXG want asset reverts rather than being priced.
    function testRevertsOnNonPaxgWantAsset() external {
        MockToken other = new MockToken("Other", "OTH", 18);
        vm.expectRevert(abi.encodeWithSelector(PaxgDynamicWithdrawFeeModule.InvalidWantAsset.selector, address(other)));
        module.calculateOfferFees(1e18, IERC20(address(shares)), IERC20(address(other)), address(0xBEEF));
    }

    /// @notice At peg (p = 1) the withdraw fee is zero.
    function testNoFeeAtPeg() external {
        _setPaxgXauPrice(PEG_PRICE);
        assertEq(_fee(100e18), 0);
    }

    /// @notice Below peg (p < 1) the withdraw fee is zero — pegged valuation already favors the vault.
    function testNoFeeBelowPeg() external {
        _setPaxgXauPrice(0.95e18);
        assertEq(_fee(100e18), 0);
    }

    /// @notice Above peg the fee is (p - 1)/p, taken in shares, so the withdrawer is paid out at max(1, p).
    function testFeeAbovePeg() external {
        // p = 2.0  =>  fee fraction = (2 - 1)/2 = 50%
        _setPaxgXauPrice(2e18);
        // 100 shares * 0.5 = 50 shares
        assertEq(_fee(100e18), 50e18);
    }

    /// @notice A small premium charges the exact (p - 1)/p fraction (cross-checked against a reference impl).
    function testFeeSmallPremium() external {
        _setPaxgXauPrice(1.02e18); // ~1.9608%
        assertEq(_fee(100e18), _expectedFee(100e18, 1.02e18));
    }

    /// @notice The residual always rounds in the vault's favor (fee rounds up).
    function testFeeRoundsUpInVaultFavor() external {
        // amount = 3 wei, p = 2.0: exact fee = 3 * 1e18 / 2e18 = 1.5, mulDivUp rounds up to 2.
        _setPaxgXauPrice(2e18);
        assertEq(_fee(3), 2);
    }

    /// @notice A stale oracle reverts the fee calculation (which reverts the whole processOrders batch).
    function testStaleOracleReverts() external {
        _setPaxgXauPrice(1.02e18);
        xauUsdFeed.setUpdatedAt(NOW - MAX_STALE - 1);
        vm.expectRevert(
            abi.encodeWithSelector(PaxgXauRateProvider.MaxTimeFromLastUpdatePassed.selector, NOW, NOW - MAX_STALE - 1)
        );
        _fee(100e18);
    }

    /// @notice For a normal-sized order, even an extreme premium leaves the fee strictly below the amount.
    function testFeeBelowAmountAtExtremePremium() external {
        _setPaxgXauPrice(100e18); // PAXG priced at 100 XAU (absurd, for bound-checking)
        uint256 fee = _fee(100e18);
        assertEq(fee, _expectedFee(100e18, 100e18)); // = 99e18
        assertLt(fee, 100e18);
    }

    /// @notice Rounding boundary: the fee rounds UP to equal the amount only when amount < p, i.e. an order
    /// smaller than the price itself (~1 wei at realistic p). WithdrawQueue.minimumOrderSize rejects such
    /// orders on submission, so this is unreachable in a real deployment without a garbage price; it is
    /// pinned here purely to document the rounding math. If it did occur, the queue refunds the order.
    function testDustOrderFeeCanEqualAmount() external {
        _setPaxgXauPrice(2e18); // exact fraction 0.5
        // amount = 1 wei (< p): exact fee 0.5, rounds up to 1 == amount.
        assertEq(_fee(1), 1);
        // amount = 2 wei (>= p): payout floor(2e18/2e18) = 1 is positive, so the fee stays below the amount.
        assertLt(_fee(2), 2);
    }

    /// @notice Fee never exceeds the order amount for any in-range price, and is zero at/below peg.
    function testFuzzFeeBounds(uint256 amount, uint256 price) external {
        amount = bound(amount, 1, 1e30);
        price = bound(price, 1, 1000e18); // PAXG:XAU in (0, 1000]
        _setPaxgXauPrice(price);

        // The mock derives paxgUsd = price * 3400e8 / 1e18, which floors; recover the actual on-chain price
        // the oracle reports so the reference impl matches exactly.
        uint256 onchainPrice = module.RATE_PROVIDER().getRate();

        uint256 fee = _fee(amount);
        assertEq(fee, _expectedFee(amount, onchainPrice));
        // <= not <: rounding up can lift a dust order's fee to exactly the amount (see testDustOrderFeeCanEqualAmount).
        assertLe(fee, amount);
        if (onchainPrice <= PEG_PRICE) {
            assertEq(fee, 0);
        }
    }

}
