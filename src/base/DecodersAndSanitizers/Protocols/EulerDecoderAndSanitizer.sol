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
    error EulerDecoderAndSanitizer__InvalidSelector();

    // @desc batch actions on Euler, in order to use an Euler vault, you must batch the actions in the EVC
    // @tag packedArgs:bytes:packed arguments depend on the selectors, this function needs a custom component in FE
    function batch(BatchItem[] calldata items) external view virtual returns (bytes memory addressesFound) {
        if (items.length != 1) revert EulerDecoderAndSanitizer__InvalidBatchLength();
        BatchItem memory item = items[0];
        if (item.onBehalfOfAccount != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();

        addressesFound = abi.encodePacked(item.tokenContract, item.value);

        bytes memory data = items[0].data;
        bytes4 selector;
        /// @solidity memory-safe-assembly
        assembly {
            selector := mload(add(data, 0x20))
        }

        // withdraw(uint256 amount, address receiver, address owner)
        if (selector == bytes4(0xb460af94)) {
            address owner;
            address receiver;
            /// @solidity memory-safe-assembly
            assembly {
                owner := mload(add(data, 0x44))
                receiver := mload(add(data, 0x64))
            }
            if (owner != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();
            if (receiver != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();
        }
        // borrow(uint256 amount, address receiver)
        // repay(uint256 amount, address receiver)
        // deposit(uint256 amount, address receiver)
        else if (selector == bytes4(0x4b3fd148) || selector == bytes4(0xacb70815) || selector == bytes4(0x6e553f65)) {
            address receiver;
            /// @solidity memory-safe-assembly
            assembly {
                receiver := mload(add(data, 0x44))
            }
            if (receiver != boringVault) revert EulerDecoderAndSanitizer__BoringVaultOnly();
        } else {
            revert EulerDecoderAndSanitizer__InvalidSelector();
        }
    }

    // @desc enable a collateral on Euler
    // @tag vault:address:the address of the vault
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

    // @desc enable a controller on Euler
    // @tag vault:address:the address of the vault
    function enableController(
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
