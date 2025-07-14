// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";

/**
 * @title AccountantChainlinkRedstoneAdapter
 * @dev Returns accountant price data in the interface of a Chainlink/Redstone oracle
 * @custom:security-contact security@molecularlabs.io
 */
contract AccountantChainlinkRedstoneAdapter is Auth {
    AccountantWithRateProviders public accountant;

    error AccountantChainlinkRedstoneAdapter__AnswerTooLargeForInt256(uint256 uint256Answer);
    error AccountantChainlinkRedstoneAdapter__NewAccountantReturnsZero();
    error AccountantChainlinkRedstoneAdapter__RateReturnsZero();

    event AccountantChainlinkRedstoneAdapter__NewAccountant(AccountantWithRateProviders indexed accountant);

    constructor(address _owner) Auth(_owner, Authority(address(0))) { }

    /**
     * @dev requires OWNER to set a new accountant
     * @param _newAccountant must not return 0 for an answer using the latestRoundData function
     */
    function setAccountant(AccountantWithRateProviders _newAccountant) external requiresAuth {
        accountant = _newAccountant;
        (, int256 answer,,,) = latestRoundData();

        if (answer == 0) {
            revert AccountantChainlinkRedstoneAdapter__NewAccountantReturnsZero();
        }

        emit AccountantChainlinkRedstoneAdapter__NewAccountant(_newAccountant);
    }

    /**
     * @dev must type cast answer to int to mimic chainlink/redstone. Will error if this cannot be done
     * @return roundId as 0
     * @return answer converted to int256, error on overflow
     * @return startedAt as 0
     * @return updatedAt as 0
     * @return answeredInRound as 0
     */
    function latestRoundData()
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 0;
        startedAt = 0;
        updatedAt = 0;
        answeredInRound = 0;

        uint256 uint256Answer = accountant.getRate();
        if (uint256Answer > uint256(type(int256).max)) {
            revert AccountantChainlinkRedstoneAdapter__AnswerTooLargeForInt256(uint256Answer);
        }
        if (uint256Answer == 0) {
            revert AccountantChainlinkRedstoneAdapter__RateReturnsZero();
        }
        answer = int256(uint256Answer);
    }

    /**
     * @dev returns the accountant's decimals
     * @return _decimals as the accountant decimals (base decimals)
     */
    function decimals() external view returns (uint8 _decimals) {
        _decimals = accountant.decimals();
    }
}
