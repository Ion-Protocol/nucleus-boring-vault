// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { RolesAuthority, Auth } from "@solmate/auth/authorities/RolesAuthority.sol";
import { BaseScript } from "./../../Base.s.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { stdJson as StdJson } from "@forge-std/StdJson.sol";
import { ConfigReader } from "../../ConfigReader.s.sol";
import { console } from "forge-std/console.sol";
import "src/helper/constants.sol";

interface IOldAccountant {

    function accountantState()
        external
        view
        returns (
            address payoutAddress,
            uint128 feesOwedInBase,
            uint128 totalSharesLastUpdate,
            uint96 exchangeRate,
            uint16 allowedExchangeRateChangeUpper,
            uint16 allowedExchangeRateChangeLower,
            uint64 lastUpdateTimestamp,
            bool isPaused,
            uint32 minimumUpdateDelayInSeconds,
            uint16 managementFee
        );

}

contract UpgradeAccountant is BaseScript {

    address constant oldAccountantAddress = address(0); // TODO: Replace with the address of the accountant to upgrade
    bytes32 SALT = makeSalt(broadcaster, true, "AccountantRedEnvelope");
    uint16 constant performanceFee = 0;
    AccountantWithRateProviders oldAccountant = AccountantWithRateProviders(oldAccountantAddress);
    RolesAuthority authority = RolesAuthority(address(oldAccountant.authority()));

    function run() public returns (address accountant) {
        (
            address _payoutAddress,,,
            uint96 _exchangeRate,
            uint16 _allowedExchangeRateChangeUpper,
            uint16 _allowedExchangeRateChangeLower,,,
            uint32 _minimumUpdateDelayInSeconds,
            uint16 _managementFee
        ) = IOldAccountant(address(oldAccountant)).accountantState();

        require(
            _allowedExchangeRateChangeUpper == 1e4, "previous accountant allowed exchange rate change upper must be 1e4"
        );
        require(
            _allowedExchangeRateChangeLower == 1e4, "previous accountant allowed exchange rate change lower must be 1e4"
        );

        // Create Contract
        bytes memory creationCode = type(AccountantWithRateProviders).creationCode;
        AccountantWithRateProviders accountant;

        bytes memory params = abi.encode(
            getMultisig(),
            oldAccountant.vault(),
            _payoutAddress,
            _exchangeRate,
            oldAccountant.base(),
            1e4,
            1e4,
            _minimumUpdateDelayInSeconds,
            _managementFee,
            performanceFee
        );

        bytes memory initCode;
        initCode = abi.encodePacked(creationCode, params);

        // Deploy
        accountant = AccountantWithRateProviders(CREATEX.deployCreate3(SALT, initCode));

        // Set the Authority of the new accountant
        bytes memory data = abi.encodeWithSelector(Auth.setAuthority.selector, authority);
        console.log("Set the authority for accountant: ", address(accountant));
        console.logBytes(data);

        // Set Authority Configurations
        data = abi.encodeWithSelector(
            RolesAuthority.setRoleCapability.selector,
            UPDATE_EXCHANGE_RATE_ROLE,
            address(accountant),
            AccountantWithRateProviders.updateExchangeRate.selector,
            true
        );
        console.log("set role capability UPDATE_EXCHANGE_RATE_ROLE for accountant: ", address(authority));
        console.logBytes(data);

        data = abi.encodeWithSelector(
            RolesAuthority.setRoleCapability.selector,
            PAUSER_ROLE,
            address(accountant),
            AccountantWithRateProviders.pause.selector,
            true
        );
        console.log("set role capability PAUSER_ROLE for accountant: ", address(authority));
        console.logBytes(data);
    }

}
