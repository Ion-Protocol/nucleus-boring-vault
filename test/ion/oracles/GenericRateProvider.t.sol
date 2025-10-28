// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { GenericRateProvider } from "./../../../src/helper/GenericRateProvider.sol";
import { SWBTC } from "./../../../src/helper/Constants.sol";

import "forge-std/Test.sol";

abstract contract GenericRateProviderTest is Test {

    GenericRateProvider rateProvider;
    address target;
    bytes4 selector;
    bytes32 staticArgument0;
    bytes32 staticArgument1;
    bytes32 staticArgument2;
    bytes32 staticArgument3;

    uint8 decimals;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString(_getRpcUrl()));

        _initialize();

        assertNotEq(address(rateProvider), address(0), "rate provider not set");
        assertGt(decimals, 0, "decimals not set");
        assertNotEq(target, address(0), "target not set");
        assertGt(bytes4(selector).length, 0, "selector not set");
    }

    function test_GetRateWithinExpectedBounds() public {
        uint256 rate = rateProvider.getRate();
        (uint256 min, uint256 max) = _expectedRateMinMax();

        assertGe(rate, min, "rate must be greater than or equal to min");
        assertLe(rate, max, "rate must be less than or equal to max");
    }

    function _initialize() public virtual;

    function _expectedRateMinMax() public virtual returns (uint256, uint256);

    function _getRpcUrl() public pure virtual returns (string memory);

}

contract SwBtcRateProviderTest is GenericRateProviderTest {

    function _initialize() public override {
        target = SWBTC;
        selector = bytes4(keccak256("pricePerShare()"));
        decimals = 8;
        staticArgument0 = bytes32(uint256(123));

        rateProvider = new GenericRateProvider(target, selector, staticArgument0, 0, 0, 0, 0, 0, 0, 0);
    }

    function _expectedRateMinMax() public view override returns (uint256 min, uint256 max) {
        min = 1 * 10 ** decimals;
        max = 1 * 10 ** decimals;
    }

    function _getRpcUrl() public pure override returns (string memory) {
        return "MAINNET_RPC_URL";
    }

}
