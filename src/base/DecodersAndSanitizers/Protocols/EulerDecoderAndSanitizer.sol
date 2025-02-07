// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseDecoderAndSanitizer } from "src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";

struct BatchItem {
    address tokenContract;
    address onBehalfOfAccount;
    uint256 value;
    bytes data;
}

abstract contract EulerDecoderAndSanitizer is BaseDecoderAndSanitizer {
    error EulerDecoderAndSanitizer__BoringVaultOnly();
    error EulerDecoderAndSanitizer__InvalidBatchLength();

    function batch(BatchItem[] calldata items) external view virtual returns (bytes memory addressesFound) {
        if (items.length != 1) revert EulerDecoderAndSanitizer__InvalidBatchLength();
        BatchItem memory item = items[0];
        if (item.onBehalfOfAccount != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();

        addressesFound = abi.encodePacked(item.tokenContract, item.value);

        bytes4 selector = abi.decode(items[0].data[:4], (bytes4));
        // withdraw(uint256 amount, address receiver)
        if (selector == bytes4(0xb460af94)) {
            (, address receiver, address owner) = abi.decode(items[0].data[4:], (uint256, address, address));
            if (owner != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();
            if (receiver != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();
        }
        // borrow(uint256 amount, address receiver)
        // repay(uint256 amount, address receiver)
        // deposit(uint256 amount, address receiver)
        else if (selector == bytes4(0x4b3fd148) || selector == bytes4(0xacb70815) || selector == bytes4(0x6e553f65)) {
            (, address receiver) = abi.decode(items[0].data[4:], (uint256, address));
            if (receiver != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();
        }
    }

    function enableCollateral(
        address account,
        address vault
    )
        external
        view
        virtual
        returns (bytes memory addressesFound)
    {
        if (account != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();
        addressesFound = abi.encodePacked(vault);
    }
}
