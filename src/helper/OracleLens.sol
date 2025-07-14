// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";

/**
 * @custom:security-contact security@molecularlabs.io
 */
contract OracleLens is Auth {
    AccountantWithRateProviders public accountant;

    error OracleLens__AnswerTooLargeForInt256(uint256 uint256Answer);
    error OracleLens__NewAccountantReturnsZero();

    event OracleLens__NewAccountant(AccountantWithRateProviders indexed accountant);

    constructor(address _owner) Auth(_owner, Authority(address(0))) { }

    /**
     * @dev requires OWNER to set a new accountant
     */
    function setAccountant(AccountantWithRateProviders _newAccountant) external requiresAuth {
        accountant = _newAccountant;
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            getLatestRoundData();

        if (answer == 0 || updatedAt == 0) {
            revert OracleLens__NewAccountantReturnsZero();
        }

        emit OracleLens__NewAccountant(_newAccountant);
    }

    /**
     * @dev must type cast answer to int to mimic chainlink. Will error if this cannot be done
     */
    function latestRoundData()
        public
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 0;
        startedAt = 0;
        answeredInRound = 0;

        (,,, uint256 uint256Answer,,, uint64 uint64UpdateTimestamp,,,) = accountant.accountantState();
        if (uint256Answer > uint256(type(int256).max)) {
            revert OracleLens__AnswerTooLargeForInt256(uint256Answer);
        }
        answer = int256(uint256Answer);
        updatedAt = uint256(uint64UpdateTimestamp);
    }

    /**
     * @dev returns the accountant's decimals
     */
    function decimals() external returns (uint8) {
        return accountant.decimals();
    }
}
