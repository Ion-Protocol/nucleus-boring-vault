// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseScript } from "../Base.s.sol";
import { LHYPEFlashswapDeleverage } from "src/helper/LHYPEFlashswapDeleverage.sol";
import { ManagerWithMerkleVerification } from "src/base/Roles/ManagerWithMerkleVerification.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { console } from "forge-std/console.sol";

contract DeployLHYPEFlashswapDeleverage is BaseScript {

    // LHYPE
    ManagerWithMerkleVerification public manager =
        ManagerWithMerkleVerification(0xe661393C409f7CAec8564bc49ED92C22A63e81d0);

    address public hypurrfiPool_hfi = 0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b;
    address public hyperlendPool_hlend = 0x00A89d7a5A02160f20150EbEA7a2b5E4879A1A8b;
    address public hyperswapPool = 0x8D64d8273a3D50E44Cc0e6F43d927f78754EdefB;

    function run() public broadcast {
        LHYPEFlashswapDeleverage hlend = new LHYPEFlashswapDeleverage(hyperlendPool_hlend, hyperswapPool, manager);

        LHYPEFlashswapDeleverage hfi = new LHYPEFlashswapDeleverage(hypurrfiPool_hfi, hyperswapPool, manager);

        console.log("hyperlend: ", address(hlend));
        console.log("hypurrfi: ", address(hfi));
    }

}
