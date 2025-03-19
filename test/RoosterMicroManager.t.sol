// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IMaverickV2Pool } from "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2Pool.sol";
import { IMaverickV2Factory } from "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2Factory.sol";
import { IMaverickV2LiquidityManager } from
    "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2LiquidityManager.sol";
import { IMaverickV2PoolLens } from "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2PoolLens.sol";
import { IMaverickV2Quoter } from "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2Quoter.sol";
import { IMaverickV2Router } from "@maverick/v2-interfaces/contracts/interfaces/IMaverickV2Router.sol";

import { RoosterMicroManager } from "src/base/MicroManagers/RoosterMicroManager.sol";

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract RoosterMicroManagerTest is Test {
    RoosterMicroManager public roosterManager;

    IMaverickV2LiquidityManager public manager =
        IMaverickV2LiquidityManager(payable(0x28d79eddBF5B215cAccBD809B967032C1E753af7));
    IMaverickV2PoolLens public lens = IMaverickV2PoolLens(0x15B4a8cc116313b50C19BCfcE4e5fc6EC8C65793);
    IMaverickV2Quoter public quoter = IMaverickV2Quoter(0xf245948e9cf892C351361d298cc7c5b217C36D82);
    IMaverickV2Router public router = IMaverickV2Router(payable(0x35e44dc4702Fd51744001E248B49CBf9fcc51f0C));

    uint256 tokenAmount = 1e18;
    uint128 liquidityAmount = 1e18;

    function setUp() public {
        // Deploy the contract with mock addresses
        roosterManager = new RoosterMicroManager(payable(manager), address(lens), address(quoter));
    }

    function testMintPositionNftToSender() public {
        // the PLUME-WETH pool
        // Fee0.50%
        // Width1.00%
        IMaverickV2Pool pool = IMaverickV2Pool(0x1A7aB8FF5db00811D0D60706877cd2f2092e2d98);

        // deal and approve tokens
        pool.tokenA().approve(address(roosterManager), 1e30);
        deal(address(pool.tokenA()), address(this), tokenAmount);

        pool.tokenB().approve(address(roosterManager), 1e30);
        deal(address(pool.tokenB()), address(this), tokenAmount);

        // get ticks and relative liquidity as they're done in Maverick tests
        (int32[] memory ticks, uint128[] memory relativeLiquidityAmounts) = _getTickAndRelativeLiquidity(pool);

        // get addSpec for params also as done in Maverick tests
        uint256 maxAmountA = 1e14;
        uint256 slippageFactor = 0.01e18;
        IMaverickV2PoolLens.AddParamsSpecification memory addSpec = IMaverickV2PoolLens.AddParamsSpecification({
            slippageFactorD18: slippageFactor,
            numberOfPriceBreaksPerSide: 0,
            targetAmount: maxAmountA,
            targetIsA: true
        });

        // get addParamsViewInputs as done in Maverick tests
        IMaverickV2PoolLens.AddParamsViewInputs memory addParamsViewInputs = IMaverickV2PoolLens.AddParamsViewInputs({
            pool: pool,
            kind: 0,
            ticks: ticks,
            relativeLiquidityAmounts: relativeLiquidityAmounts,
            addSpec: addSpec
        });

        console2.log("beforeAddLiquidity A: ", pool.tokenA().balanceOf(address(this)));
        console2.log("beforeAddLiquidity B: ", pool.tokenB().balanceOf(address(this)));

        uint256 id = roosterManager.mintPositionNftToSender(addParamsViewInputs, block.timestamp + 30, 0, 300e18);
        assertTrue(manager.position().ownerOf(id) == address(this));

        console2.log("afterAddLiquidity A: ", pool.tokenA().balanceOf(address(this)));
        console2.log("afterAddLiquidity B: ", pool.tokenB().balanceOf(address(this)));

        manager.position().approve(address(roosterManager), id);

        console2.log("beforeRemoveLiquidity A: ", pool.tokenA().balanceOf(address(this)));
        console2.log("beforeRemoveLiquidity B: ", pool.tokenB().balanceOf(address(this)));
        IMaverickV2Pool.RemoveLiquidityParams memory removeLiquidityParams =
            manager.position().getRemoveParams(id, 0, 1e18);
        console2.log("removeLiquidityParams.amounts[0]: ", removeLiquidityParams.amounts[0]);
        console2.log("removeLiquidityParams.amounts[1]: ", removeLiquidityParams.amounts[1]);
        roosterManager.removeLiquidity(pool, id, removeLiquidityParams, block.timestamp + 30, 0, 300e18);
        console2.log("afterRemoveLiquidity A: ", pool.tokenA().balanceOf(address(this)));
        console2.log("afterRemoveLiquidity B: ", pool.tokenB().balanceOf(address(this)));

        assertTrue(pool.tokenA().balanceOf(address(this)) == 1e30);
        assertTrue(pool.tokenB().balanceOf(address(this)) == 1e30);
    }

    // function ripped from Maverick tests
    function _getTickAndRelativeLiquidity(IMaverickV2Pool pool)
        internal
        view
        returns (int32[] memory ticks, uint128[] memory relativeLiquidityAmounts)
    {
        int32 activeTick = pool.getState().activeTick;
        ticks = new int32[](5);
        (ticks[0], ticks[1], ticks[2], ticks[3], ticks[4]) =
            (activeTick - 2, activeTick - 1, activeTick, activeTick + 1, activeTick + 2);

        // relative liquidity amounts are in the liquidity domain, not the LP
        // balance domain. i.e. these are the values a user might input into
        // the addLiquidity bar-graph screen in the app.mav.xyz app.  the scale
        // is relative, but larger numbers are better as they allow more
        // precision in the deltaLPBalance calculation.
        relativeLiquidityAmounts = new uint128[](5);
        (
            relativeLiquidityAmounts[0],
            relativeLiquidityAmounts[1],
            relativeLiquidityAmounts[2],
            relativeLiquidityAmounts[3],
            relativeLiquidityAmounts[4]
        ) = (liquidityAmount, liquidityAmount, liquidityAmount, liquidityAmount, liquidityAmount);
    }
}
