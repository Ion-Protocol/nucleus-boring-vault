// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";

/**
 * @custom:security-contact security@molecularlabs.io
 */
contract MonotonicExchangeRateOracle is Auth {
    AccountantWithRateProviders public accountant;
    uint8 public accountantDecimals;

    // Stores in the Accountant Decimals, conversion to 18 decimals is done at the return step
    uint256 public highwaterMark;

    event MonotonicExchangeRateOracle__HighwaterMarkUpdated(uint256 newHighwaterMark);
    event MonotonicExchangeRateOracle__AccountantUpdated(AccountantWithRateProviders newAccountant);

    error MonotonicExchangeRateOracle__NewAccountantDecimalsMissmatch();

    constructor(address _owner, AccountantWithRateProviders _accountant) Auth(_owner, Authority(address(0))) {
        accountant = _accountant;
        accountantDecimals = _accountant.decimals();
    }

    /**
     * @dev setAccountant and the decimals as reported
     */
    function setAccountant(AccountantWithRateProviders _newAccountant) external requiresAuth {
        accountant = _newAccountant;
        if (accountant.decimals() != accountantDecimals) {
            revert MonotonicExchangeRateOracle__NewAccountantDecimalsMissmatch();
        }
        emit MonotonicExchangeRateOracle__AccountantUpdated(_newAccountant);
    }

    /**
     * @dev setHighwaterMark manually, must be done in accountantDecimals
     */
    function setHighwaterMark(uint256 _newHighwaterMark) external requiresAuth {
        highwaterMark = _newHighwaterMark;
        emit MonotonicExchangeRateOracle__HighwaterMarkUpdated(_newHighwaterMark);
    }

    /**
     * @dev function to return accountant's getRate but with the following considerations:
     *  1. The rate must never go down
     *  2. The rate must be returned in 18 decimals
     */
    function getRate() external returns (uint256) {
        uint256 rate = accountant.getRate();
        if (rate > highwaterMark) {
            highwaterMark = rate;
            emit MonotonicExchangeRateOracle__HighwaterMarkUpdated(highwaterMark);
        }
        return _convertTo18Decimals(highwaterMark);
    }

    /**
     * @dev function to return the highwater mark in 18 decimals.
     * NOTE: View only, does not query accountant or update the highwater mark, should NOT be used as the oracle
     * function
     */
    function getHighwaterMark18Decimals() external view returns (uint256) {
        return _convertTo18Decimals(highwaterMark);
    }

    /**
     * @dev convert a rate to 18 decimals before returning in getRate
     */
    function _convertTo18Decimals(uint256 _rate) internal view returns (uint256) {
        if (accountantDecimals == 18) {
            return _rate;
        } else if (accountantDecimals < 18) {
            uint8 diff = 18 - accountantDecimals;
            return _rate * 10 ** diff;
        } else {
            uint8 diff = accountantDecimals - 18;
            return _rate / 10 ** diff;
        }
    }
}
