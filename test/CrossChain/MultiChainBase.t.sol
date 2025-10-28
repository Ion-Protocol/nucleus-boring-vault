// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { CrossChainBaseTest, ERC20 } from "./CrossChainBase.t.sol";
import "src/base/Roles/CrossChain/MultiChainTellerBase.sol";

abstract contract MultiChainBaseTest is CrossChainBaseTest {

    function setUp() public virtual override {
        super.setUp();
    }

    function testReverts() public virtual override {
        MultiChainTellerBase sourceTeller = MultiChainTellerBase(sourceTellerAddr);
        MultiChainTellerBase destinationTeller = MultiChainTellerBase(destinationTellerAddr);

        // Adding a chain with a zero message gas limit should revert.
        vm.expectRevert(bytes(abi.encodeWithSelector(MultiChainTellerBase_ZeroMessageGasLimit.selector)));
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 0, 0);

        // Allowing messages to a chain with a zero message gas limit should revert.
        vm.expectRevert(bytes(abi.encodeWithSelector(MultiChainTellerBase_ZeroMessageGasLimit.selector)));
        sourceTeller.allowMessagesToChain(DESTINATION_SELECTOR, address(destinationTeller), 0);

        // Changing the gas limit to zero should revert.
        vm.expectRevert(bytes(abi.encodeWithSelector(MultiChainTellerBase_ZeroMessageGasLimit.selector)));
        sourceTeller.setChainGasLimit(DESTINATION_SELECTOR, 0);

        // But you can add a chain with a non-zero message gas limit, if messages to are not supported.
        uint32 newChainSelector = 3;
        sourceTeller.addChain(newChainSelector, true, false, address(destinationTeller), 0, 0);

        // Trying to send messages to a chain that is not supported should revert.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(MultiChainTellerBase_MessagesNotAllowedTo.selector, DESTINATION_SELECTOR))
        );

        BridgeData memory data =
            BridgeData(DESTINATION_SELECTOR, address(this), ERC20(NATIVE), 80_000, abi.encode(DESTINATION_SELECTOR));
        sourceTeller.bridge(1e18, data);

        // setup chains.
        sourceTeller.addChain(DESTINATION_SELECTOR, true, true, address(destinationTeller), 100_000, 0);
        destinationTeller.addChain(SOURCE_SELECTOR, true, true, address(sourceTeller), 100_000, 0);

        // if too much gas is used, revert
        data = BridgeData(
            DESTINATION_SELECTOR,
            address(this),
            ERC20(NATIVE),
            CHAIN_MESSAGE_GAS_LIMIT + 1,
            abi.encode(DESTINATION_SELECTOR)
        );
        vm.expectRevert(abi.encodeWithSelector(MultiChainTellerBase_GasLimitExceeded.selector));
        sourceTeller.bridge(1e18, data);

        // if min gas is set too high, revert
        sourceTeller.addChain(
            DESTINATION_SELECTOR,
            true,
            true,
            address(destinationTeller),
            CHAIN_MESSAGE_GAS_LIMIT,
            CHAIN_MESSAGE_GAS_LIMIT
        );
        data = BridgeData(DESTINATION_SELECTOR, address(this), ERC20(NATIVE), 80_000, abi.encode(DESTINATION_SELECTOR));
        vm.expectRevert(abi.encodeWithSelector(MultiChainTellerBase_GasTooLow.selector));
        sourceTeller.bridge(1e18, data);
    }

}
