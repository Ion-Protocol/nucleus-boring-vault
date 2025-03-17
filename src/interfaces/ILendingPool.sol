// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface ILendingPool {
    /**
     * @notice Initiates a flash loan.
     * @param receiverAddress The address receiving the flash loaned amounts.
     * @param assets The addresses of the assets being flash loaned.
     * @param amounts The amounts being flash loaned for each asset.
     * @param modes Types of debt to open if the flash loan is not returned (0 means no debt, i.e. flash loan).
     * @param onBehalfOf Address that will receive the debt if a non-zero mode is used.
     * @param params Variadic packed params to pass to the receiver as extra information.
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     */
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    )
        external;
}
