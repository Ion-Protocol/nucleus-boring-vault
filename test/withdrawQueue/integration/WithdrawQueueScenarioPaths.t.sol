// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { WithdrawQueue } from "src/base/Roles/WithdrawQueue.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { WithdrawQueueIntegrationBaseTest } from "./WithdrawQueueIntegrationBaseTest.t.sol";

contract WithdrawQueueScenarioPathsTest is WithdrawQueueIntegrationBaseTest {

    function test_QueuePathsWithExchangeRateChanges(uint96 r0, uint96 r1, uint96 r2) external {
        // test a single order in the queue along the submit, process, submit cancel, submit force process, and submit
        // fail transfer paths with exchange rate changes.
        // r0 = rate at time of subission
        // r1 = rate at time of refund or force process
        // r2 = rate at time of process
        r0 = (r0 % uint96(10 * 10 ** accountant.decimals())) + 1;
        r1 = (r1 % uint96(10 * 10 ** accountant.decimals())) + 1;
        r2 = (r2 % uint96(10 * 10 ** accountant.decimals())) + 1;

        // happy path (normal process)
        _happyPath(1e6, r0, r2);

        /// TODO: May need to make these separate tests, as in extreeme cases like the truncation to a 0 assets back,
        /// the queue can get stuck and prevent future flows... Or we can bound these better...

        // cancel path (user cancels and then gets processed)
        _cancelPath(1e6, r0, r1, r2);
    }

}

