// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { Test, console } from "@forge-std/Test.sol";
import { OneInchWrapper, AggregationRouterV6 } from "src/helper/OneInchWrapper.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { CrossChainTellerBase, BridgeData } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";

string constant DEFAULT_RPC_URL = "L1_RPC_URL";

contract OneInchWrapperTest is Test {
    OneInchWrapper wrapper;
    uint256 constant depositAm = 100_000_000;
    address constant srcToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant dstToken = 0x15700B564Ca08D9439C58cA5053166E8317aa138;
    address constant agg = 0x111111125421cA6dc452d289314280a0f8842A65;
    address constant executor = 0x5141B82f5fFDa4c6fE1E372978F1C5427640a190;

    CrossChainTellerBase constant teller = CrossChainTellerBase(0xd65D39c859C6754B3BC14f5c03c4A1aE80FC4c15);

    function setUp() external {
        _startFork(DEFAULT_RPC_URL);

        wrapper = new OneInchWrapper(
            ERC20(dstToken), // srcToken
            teller, // earnETH Teller
            AggregationRouterV6(agg) // OneInch Aggregator
        );
        console.log("construction complete");
    }

    function testWrapper() external {
        AggregationRouterV6.SwapDescription memory desc = AggregationRouterV6.SwapDescription({
            srcToken: ERC20(srcToken),
            dstToken: ERC20(dstToken),
            srcReceiver: payable(executor),
            dstReceiver: payable(address(wrapper)),
            amount: depositAm,
            minReturnAmount: 99_927_739_338_702_407_010,
            flags: 0
        });

        bytes memory data =
            hex"0000000000000000000000000000000000000000000000ab00007d00001a0020d6bdbf78a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4802a00000000000000000000000000000000000000000000000000000000000000001ee63c1e580e780df05ed3d1d29b35edaf9c8f3131e9f4c799ea0b86991c6218b36c1d19d4a2e9eb0ce3606eb48111111125421ca6dc452d289314280a0f8842a650020d6bdbf7815700b564ca08d9439c58ca5053166e8317aa138111111125421ca6dc452d289314280a0f8842a65";
        console.logBytes(data);

        console.log("pre-deal");
        deal(srcToken, address(this), depositAm);
        console.log("post deal");
        ERC20(srcToken).approve(address(wrapper), depositAm);
        console.log("post approve");

        console.log("Fails here?:");
        wrapper.deposit(0, executor, desc, data);
        console.log("No");
        uint256 endShareBal = teller.vault().balanceOf(address(this));
        console.log("Balance of shares: ", endShareBal);
        assertGt(endShareBal, 0, "should have some dstToken");
    }

    function _startFork(string memory rpcKey) internal virtual returns (uint256 forkId) {
        if (block.chainid == 31_337) {
            forkId = vm.createFork(vm.envString(rpcKey));
            vm.selectFork(forkId);
        }
    }
}
