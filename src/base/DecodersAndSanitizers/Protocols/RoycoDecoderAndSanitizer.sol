// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

interface IWeirollWallet {

    function owner() external view returns (address);

}

abstract contract RoycoDecoderAndSanitizer is BaseDecoderAndSanitizer {

    error RoycoDecoderAndSanitizer__FundingVaultMustBeZeroAddress();
    error RoycoDecoderAndSanitizer__OwnerMustBeBoringVault();

    // @desc function to enter a Royco recipe vault, fundingVault must be the zero address
    // @tag frontendFeeRecipient:address:address of the frontend fee recipient
    function fillIPOffers(
        bytes32[] calldata ipOfferHashes,
        uint256[] calldata fillAmounts,
        address fundingVault,
        address frontendFeeRecipient
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        if (fundingVault != address(0)) {
            revert RoycoDecoderAndSanitizer__FundingVaultMustBeZeroAddress();
        }
        addressesFound = abi.encodePacked(fundingVault, frontendFeeRecipient);
    }

    // @desc function to claim rewards from a Royco recipe vault, weirollWallet must be owned by boringVault
    // @tag incentiveToken:address:address of the incentive token
    // @tag to:address:address of the recipient of incentiveToken
    function claim(
        address weirollWallet,
        address incentiveToken,
        address to
    )
        external
        view
        returns (bytes memory addressesFound)
    {
        if (IWeirollWallet(weirollWallet).owner() != boringVault) {
            revert RoycoDecoderAndSanitizer__OwnerMustBeBoringVault();
        }
        addressesFound = abi.encodePacked(incentiveToken, to);
    }

    // @desc function to execute a withdrawal from a Royco recipe vault, weirollWallet must be owned by boringVault
    function executeWithdrawalScript(address weirollWallet) external view returns (bytes memory addressesFound) {
        if (IWeirollWallet(weirollWallet).owner() != boringVault) {
            revert RoycoDecoderAndSanitizer__OwnerMustBeBoringVault();
        }
        addressesFound = abi.encodePacked();
    }

}
