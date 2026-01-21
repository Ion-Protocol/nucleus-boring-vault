// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20 } from "@solmate/tokens/ERC20.sol";

interface LevelReserveLens {

    function getRedeemPrice(address asset) external view returns (uint256);

}

interface SlvlUSD {

    function decimals() external view returns (uint8);
    function previewRedeem(uint256 amount) external view returns (uint256);

}

contract SlvlUSDRateProvider {

    SlvlUSD constant SLVL_USD = SlvlUSD(0x4737D9b4592B40d51e110b94c9C043c6654067Ae);
    LevelReserveLens constant LVL_LENS = LevelReserveLens(0xd7f68a32E4bdd4908bDD1daa03bDd04581De80Ff);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // @notice The value of slvlUSD in USDC terms.
    // @dev USDC / slvlUSD = USDC / lvlUSD * lvlUSD / slvlUSD
    // @returns USDC / slvlUSD in the Teller quote asset decimals which is
    // lvlUSD with 18 decimals.
    function getRate() external view returns (uint256) {
        // 18 decimals slvlUSD.decimals();
        uint256 lvlUSDPerSlvlUSD = SLVL_USD.previewRedeem(10 ** SLVL_USD.decimals()); // lvlUSD / slvlUSD

        // Returns in the same decimals as the collateral token
        // USDC is collateral token, so 6 decimals.
        uint256 USDCPerLvlUSD = LVL_LENS.getRedeemPrice(address(USDC)); // USDC / lvlUSD

        // [18 decimals] * [6 decimals] / [6 decimals] = [18 decimals]
        uint256 USDCPerSlvlUSD = lvlUSDPerSlvlUSD * USDCPerLvlUSD / 10 ** USDC.decimals();

        return USDCPerSlvlUSD;
    }

}
