// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BoringVault } from "./BoringVault.sol";
import { Accountant } from "./Roles/Accountant.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { IVelodromeV1Router } from "../interfaces/IVelodromeV1Router.sol";

/**
 * @title VelodromeBuyback
 * @dev no permissioned functions, as token destinations will always be the vault or the sender of tokens
 * @custom:security-contact security@molecularlabs.io
 */
contract VelodromeBuyback {
    /**
     * @notice The VelodromeV1 router contract used for swapping assets
     */
    IVelodromeV1Router public immutable exchange;

    /**
     * @notice The accountant contract
     */
    Accountant public immutable accountant;

    error BuyBackBot__NotEnoughQuoteAssetReceived(uint256 expected, uint256 actual);

    constructor(address _exchange, Accountant _accountant) {
        exchange = IVelodromeV1Router(_exchange);
        accountant = _accountant;
    }

    /**
     * @notice Buys boring vault tokens with a quote asset and verifies the swap rate against the accountant's rate
     * @dev Takes user's tokens, swaps them for vault tokens, and verifies that the rate received is at least
     *      as good as the rate from the accountant
     * @param quoteAsset The ERC20 token to use for purchasing vault tokens
     * @param amount The amount of quote asset to spend
     */
    function buyAndSwapEnforcingRate(ERC20 quoteAsset, uint256 amount) external {
        quoteAsset.transferFrom(msg.sender, address(this), amount);
        quoteAsset.approve(address(exchange), amount);

        BoringVault vault = accountant.vault();

        uint256[] memory amounts = exchange.swapExactTokensForTokensSimple(
            amount, -1, address(quoteAsset), address(vault), true, address(this), block.timestamp + 9
        );
        uint256 amountReceived = amounts[amounts.length - 1];

        uint256 rateInQuote = accountant.getRateInQuote(quoteAsset);

        if (amountReceived < amount * 1e18 / rateInQuote) {
            revert BuyBackBot__NotEnoughQuoteAssetReceived(amount * 1e18 / rateInQuote, amounts[amounts.length - 1]);
        }

        vault.transfer(msg.sender, amountReceived);
    }

    /// @dev function to prevent tokens from being locked in the bot, ONLY able to be collected to the vault
    function sweepDustToVault(ERC20 token) external {
        token.transfer(address(accountant.vault()), token.balanceOf(address(this)));
    }
}
