// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

interface LevelReserveLens {

    function getRedeemPrice(address asset) external view returns (uint256);

}

contract LvlUSDRateProvider {

    LevelReserveLens constant LVL_LENS = LevelReserveLens(0xd7f68a32E4bdd4908bDD1daa03bDd04581De80Ff);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // @notice The value of lvlUSD in USDC terms.
    // @dev At deposit time, to ensure collateral backing, Level wants to
    // 'underestimate' the value of the collateral being deposited. At
    // redemption time, to ensure collateral backing, Level wants to
    // 'overestimate' the value of the collateral being redeemed. The lvlUSD
    // oracle returns USD per USDC value, so we need to convert that to USDC per
    // lvlUSD.
    // @returns USDC / slvlUSD in the Teller quote asset decimals which is
    // lvlUSD with 18 decimals.
    function getRate() external view returns (uint256) {
        // Returns in the same decimals as the collateral token
        // USDC is collateral token, so 6 decimals.
        uint256 USDCPerLvlUSD = LVL_LENS.getRedeemPrice(address(USDC)); // USDC / lvlUSD

        return USDCPerLvlUSD * 10 ** 12; // convert 6 decimals to 18 decimals
    }

}
