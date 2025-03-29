// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BoringVault } from "./BoringVault.sol";
import { TellerWithMultiAssetSupport } from "./Roles/TellerWithMultiAssetSupport.sol";
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
     * @notice The LHYPE vault
     */
    BoringVault public immutable LHYPE;

    /**
     * @notice The teller contract for LHYPE
     */
    TellerWithMultiAssetSupport public immutable teller;

    error BuyBackBot__NotEnoughQuoteAssetReceived(uint256 expected, uint256 actual);

    constructor(address _exchange, TellerWithMultiAssetSupport _teller) {
        exchange = IVelodromeV1Router(_exchange);
        LHYPE = _teller.vault();
        teller = _teller;
    }

    /**
     * @notice Buys LHYPE tokens with a quote asset and verifies the swap rate against the accountant's rate
     * @dev Takes user's tokens, swaps them for LHYPE, and verifies that the rate received is at least
     *      as good as the rate from the accountant
     * @param quoteAsset The ERC20 token to use for purchasing LHYPE
     * @param amount The amount of quote asset to spend
     */
    function buyAndSwapEnforcingRate(ERC20 quoteAsset, uint256 amount) external {
        quoteAsset.transferFrom(msg.sender, address(this), amount);
        quoteAsset.approve(address(exchange), amount);

        uint256[] memory amounts = exchange.swapExactTokensForTokensSimple(
            amount, 0, address(quoteAsset), address(LHYPE), true, address(this), block.timestamp + 10
        );
        uint256 amountReceived = amounts[amounts.length - 1];

        uint256 rateInQuote = teller.accountant().getRateInQuote(quoteAsset);

        if (amountReceived < amount * 1e18 / rateInQuote) {
            revert BuyBackBot__NotEnoughQuoteAssetReceived(amount * 1e18 / rateInQuote, amounts[amounts.length - 1]);
        }

        LHYPE.transfer(msg.sender, amountReceived);
    }

    /// @dev function to prevent tokens from being locked in the bot, ONLY able to be collected to the vault
    function sweepDustToVault(ERC20 token) external {
        token.transfer(address(LHYPE), token.balanceOf(address(this)));
    }
}
