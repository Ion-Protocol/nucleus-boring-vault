// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {CrossChainTellerBase, BridgeData, ERC20} from "./CrossChainTellerBase.sol";
import {OAppAuth, MessagingFee, Origin } from "./OAppAuth/OAppAuth.sol";
import {console} from "@forge-std/Test.sol";
import {Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import {Auth} from "@solmate/auth/Auth.sol";

contract CrossChainLayerZeroTellerWithMultiAssetSupport is CrossChainTellerBase, OAppAuth{
    
    constructor(address _owner, address _vault, address _accountant, address _weth, address _endpoint)
        CrossChainTellerBase(_owner, _vault, _accountant, _weth)
        OAppAuth(_endpoint, _owner) 
    {

    }

    function _bridge(BridgeData calldata data) internal override returns(bytes32){
        return 0;
    }

}