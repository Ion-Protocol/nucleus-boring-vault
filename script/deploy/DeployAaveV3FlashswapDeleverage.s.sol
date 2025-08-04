// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseScript } from "../Base.s.sol";
import { LHYPEFlashswapDeleverage } from "src/helper/AaveV3FlashswapDeleverage.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { console } from "forge-std/console.sol";

contract DeployLHYPEFlashswapDeleverage is BaseScript {
    // LHYPE
    BoringVault public boringVault = BoringVault(payable(0x5748ae796AE46A4F1348a1693de4b50560485562));

    address public hypurrfiPool_hfi = 0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b;
    address public hyperlendPool_hlend = 0x00A89d7a5A02160f20150EbEA7a2b5E4879A1A8b;
    address public hyperswapPool = 0x8D64d8273a3D50E44Cc0e6F43d927f78754EdefB;

    function run() public broadcast {
        LHYPEFlashswapDeleverage hlend = new LHYPEFlashswapDeleverage(hyperlendPool_hlend, hyperswapPool, boringVault);

        LHYPEFlashswapDeleverage hfi = new LHYPEFlashswapDeleverage(hypurrfiPool_hfi, hyperswapPool, boringVault);

        console.log("hyperlend: ", address(hlend));
        console.log("hypurrfi: ", address(hfi));
    }
}
