// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { BaseScript } from "../Base.s.sol";
import { AaveV3FlashswapDeleverage } from "src/helper/AaveV3FlashswapDeleverage.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { console } from "forge-std/console.sol";

contract DeployAaveV3FlashswapDeleverage is BaseScript {
    // LHYPE
    BoringVault public boringVault = BoringVault(payable(0x5748ae796AE46A4F1348a1693de4b50560485562));

    address wstHYPE = 0x94e8396e0869c9F2200760aF0621aFd240E1CF38;
    address stHYPE = 0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1;
    address WHYPE = 0x5555555555555555555555555555555555555555;

    address public hypurrfiPool_hfi = 0xceCcE0EB9DD2Ef7996e01e25DD70e461F918A14b;
    address public hyperlendPool_hlend = 0x00A89d7a5A02160f20150EbEA7a2b5E4879A1A8b;
    address public hyperswapPool = 0x8D64d8273a3D50E44Cc0e6F43d927f78754EdefB;

    function run() public broadcast {
        AaveV3FlashswapDeleverage hlend =
            new AaveV3FlashswapDeleverage(hyperlendPool_hlend, hyperswapPool, boringVault, wstHYPE, WHYPE);

        AaveV3FlashswapDeleverage hfi =
            new AaveV3FlashswapDeleverage(hypurrfiPool_hfi, hyperswapPool, boringVault, wstHYPE, WHYPE);

        console.log("hyperlend: ", address(hlend));
        console.log("hypurrfi: ", address(hfi));
    }
}
