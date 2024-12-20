pragma solidity 0.8.21;

import { IRateProvider } from "src/interfaces/IRateProvider.sol";

import { IPMarket } from "lib/ion-protocol/lib/pendle-core-v2-public/contracts/interfaces/IPMarket.sol";

import { IStandardizedYield } from
    "lib/ion-protocol/lib/pendle-core-v2-public/contracts/interfaces/IStandardizedYield.sol";

import { IPPrincipalToken } from "lib/ion-protocol/lib/pendle-core-v2-public/contracts/interfaces/IPPrincipalToken.sol";

import { IPPtLpOracle } from "lib/ion-protocol/lib/pendle-core-v2-public/contracts/interfaces/IPPtLpOracle.sol";

error PendlePTRateProvider__InvalidDecimals(uint256 decimals);

/**
 * @title PendlePTRateProvider
 * @custom:security-contact security@molecularlabs.io
 */
contract PendlePTRateProvider is IRateProvider {
    /// @notice constant values
    IPPtLpOracle public constant ORACLE = IPPtLpOracle(0x14030836AEc15B2ad48bB097bd57032559339c92);
    uint32 public constant DURATION = 1 days;

    /// @notice the pendle market this rate provider serves
    IPMarket public immutable market;

    /// @param pendleMarket to serve the PT rate
    constructor(IPMarket pendleMarket) {
        market = pendleMarket;
    }

    /// @notice getRate for a Pendle PT token
    function getRate() external view returns (uint256) {
        (IStandardizedYield sy, IPPrincipalToken pt,) = market.readTokens();
        uint256 syRate = sy.exchangeRate();
        uint256 ptRate = ORACLE.getPtToAssetRate(address(market), DURATION);
        if (sy.decimals() != 18 || pt.decimals() != 18) {
            revert PendlePTRateProvider__InvalidDecimals(sy.decimals());
        }
        return syRate * ptRate / 1e18;
    }
}
