// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { WithdrawQueue } from "src/base/Roles/WithdrawQueue.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { WithdrawQueueIntegrationBaseTest } from "./WithdrawQueueIntegrationBaseTest.t.sol";

contract WithdrawQueueScenarioPathsTest is WithdrawQueueIntegrationBaseTest {

    function test_HappyPathsWithExchangeRateChanges(uint96 r0, uint96 r1, uint96 r2) external {
        // r0 = rate at time of subission
        // r1 = rate at time of refund or force process
        // r2 = rate at time of process
        r0 = (r0 % uint96(10 * 10 ** accountant.decimals())) + 1;
        r1 = (r1 % uint96(10 * 10 ** accountant.decimals())) + 1;
        r2 = (r2 % uint96(10 * 10 ** accountant.decimals())) + 1;

        // happy path (normal process)
        _happySubmitAndProcessAllPath(1e6, r0);
        _happyPath(1e6, r0, r2);
    }

    function test_CancelPathWithExchangeRateChanges(uint96 r0, uint96 r1, uint96 r2) external {
        // r0 = rate at time of subission
        // r1 = rate at time of refund or force process
        // r2 = rate at time of process
        r0 = (r0 % uint96(10 * 10 ** accountant.decimals())) + 1;
        r1 = (r1 % uint96(10 * 10 ** accountant.decimals())) + 1;
        r2 = (r2 % uint96(10 * 10 ** accountant.decimals())) + 1;

        // cancel path (user cancels and then gets processed)
        _cancelPath(1e6, r0, r1, r2);
    }

    function test_ForceProcessPathWithExchangeRateChanges(uint96 r0, uint96 r1, uint96 r2) external {
        // r0 = rate at time of subission
        // r1 = rate at time of refund or force process
        // r2 = rate at time of process
        r0 = (r0 % uint96(10 * 10 ** accountant.decimals())) + 1;
        r1 = (r1 % uint96(10 * 10 ** accountant.decimals())) + 1;
        r2 = (r2 % uint96(10 * 10 ** accountant.decimals())) + 1;

        // force process path (user forces process and then gets processed)
        _forceProcessPath(1e6, r0, r1, r2);
    }

}
