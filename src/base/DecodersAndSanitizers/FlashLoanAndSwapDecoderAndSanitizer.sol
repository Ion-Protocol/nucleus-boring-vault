// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

abstract contract FlashLoanAndSwapDecoderAndSanitizer {
    function flashLoanBalancer(
        address poolAddress,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
    )
        external
        view
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(poolAddress, msg.sender, tokens[0]);
        return addressesFound;
    }

    function flashLoanAave(
        address poolAddress,
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        bytes calldata userData
    )
        external
        view
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(poolAddress, msg.sender, tokens[0]);
        return addressesFound;
    }

    function flashLoanMorpho(
        address poolAddress,
        address token,
        uint256 assets,
        bytes calldata userData
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(poolAddress, token);
        return addressesFound;
    }

    function swapUniswapV3(
        address poolAddress,
        bool zeroForOne,
        int256 amountSpecified,
        bytes calldata userData
    )
        external
        pure
        returns (bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(poolAddress);
        return addressesFound;
    }
}
