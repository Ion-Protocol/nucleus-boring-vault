// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {CrossChainTellerBase, BridgeData, ERC20} from "./CrossChainTellerBase.sol";

import {console} from "@forge-std/Test.sol";

contract CrossChainLayerZeroTellerWithMultiAssetSupport is CrossChainTellerBase{
    
    constructor(address _owner, address _vault, address _accountant, address _weth)
        CrossChainTellerBase(_owner, _vault, _accountant, _weth)
    {

    }

    function _bridge(BridgeData calldata data) internal override returns(bytes32){
        return 0;
    }

}