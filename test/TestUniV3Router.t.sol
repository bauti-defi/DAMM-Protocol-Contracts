// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";

import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";
import {Router} from "@src/Router.sol";

import {BaseUniswap} from "@test/base/BaseUniswap.sol";
import {TokenMinter} from "@test/base/TokenMinter.sol";

import {UniswapTestHelper} from "@test/utils/UniswapTestHelper.sol";

import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";

contract TestUniswapV3Router is BaseUniswap, TokenMinter, UniswapTestHelper {
    uint256 constant BIG_NUMBER = 10 ** 4;

    address public deployer;
    address public trader;
    Router public router;

    constructor() UniswapTestHelper(uniswapV3SwapRouter, uniswapV3PositionManager) {}

    function setUp() public override(BaseUniswap, TokenMinter) {
        super.setUp();

        deployer = makeAddr("DEPLOYER");

        address[] memory tokenWhitelist = new address[](2);
        tokenWhitelist[0] = address(USDC);
        tokenWhitelist[1] = address(USDCe);

        vm.prank(deployer);
        router = new Router(deployer, address(uniswapV3PositionManager), address(uniswapV3SwapRouter), tokenWhitelist);
        vm.label(address(router), "ROUTER");

        assertEq(router.owner(), deployer);
        assertEq(address(router.uniswapV3PositionManager()), address(uniswapV3PositionManager));
        assertEq(address(router.uniswapV3SwapRouter()), address(uniswapV3SwapRouter));
        assertTrue(router.isTokenWhitelisted(address(USDC)));
        assertTrue(router.isTokenWhitelisted(address(USDCe)));
        assertEq(USDC.balanceOf(address(router)), 0);
        assertEq(USDCe.balanceOf(address(router)), 0);

        trader = makeAddr("TRADER");

        address pool = address(_getPool(address(USDC), address(USDCe), 100));
        vm.label(pool, "UniswapPool");

        // give trader tokens
        mintUSDC(trader, BIG_NUMBER);
        mintUSDCe(trader, BIG_NUMBER);
    }

    modifier withApprovals() {
        vm.startPrank(trader);
        USDC.approve(address(router), BIG_NUMBER);
        USDCe.approve(address(router), BIG_NUMBER);
        IERC721(address(uniswapV3PositionManager)).setApprovalForAll(address(router), true);
        vm.stopPrank();
        _;
    }

    modifier invariants() {
        assertEq(USDC.balanceOf(address(router)), 0);
        assertEq(USDCe.balanceOf(address(router)), 0);
        if (IERC721(address(uniswapV3PositionManager)).balanceOf(address(trader)) > 0) {
            assertEq(IERC721(address(uniswapV3PositionManager)).ownerOf(POSITION_ID), trader);
        }
        _;
        if (IERC721(address(uniswapV3PositionManager)).balanceOf(address(trader)) > 0) {
            assertEq(IERC721(address(uniswapV3PositionManager)).ownerOf(POSITION_ID), trader);
        }
        assertEq(USDC.balanceOf(address(router)), 0);
        assertEq(USDCe.balanceOf(address(router)), 0);
    }

    function test_mint_position() public invariants withApprovals {
        uint256 startingPositionCount = _getUniV3PositionCount(trader);

        INonfungiblePositionManager.MintParams memory params =
            _mintPositionParameter(trader, address(USDC), address(USDCe), 100, 100, 100);

        vm.prank(trader);
        router.mintV3Position(params);

        uint256 endingPositionCount = _getUniV3PositionCount(trader);
        assertTrue(endingPositionCount == startingPositionCount + 1);
    }

    function test_decrease_liquidity() public invariants withApprovals {
        INonfungiblePositionManager.MintParams memory mintParams =
            _mintPositionParameter(trader, address(USDC), address(USDCe), 100, 100, 100);

        vm.prank(trader);
        router.mintV3Position(mintParams);

        uint128 decreaseAmount = 5;

        (,,,,,,, uint128 start_Liquidity,,,,) =
            INonfungiblePositionManager(address(uniswapV3PositionManager)).positions(POSITION_ID);

        // check the position was minted with liquidity
        assertTrue(start_Liquidity > 0);

        // now we roll the fork forward to catch some swaps
        vm.rollFork(BLOCK_NUMBER + 10_000);

        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams =
            INonfungiblePositionManager.DecreaseLiquidityParams(POSITION_ID, decreaseAmount, 0, 0, _mockTimestamp());

        vm.startPrank(trader);
        router.decreaseV3PositionLiquidity(decreaseParams);
        vm.stopPrank();

        (,,,,,,, uint128 end_Liquidity,,,,) =
            INonfungiblePositionManager(address(uniswapV3PositionManager)).positions(POSITION_ID);

        // make sure trader is still owner of position
        assertEq(IERC721(address(uniswapV3PositionManager)).ownerOf(POSITION_ID), trader);
        assertEq(start_Liquidity, end_Liquidity + decreaseAmount);
    }

    function test_increase_liquidity() public invariants withApprovals {
        INonfungiblePositionManager.MintParams memory mintParams =
            _mintPositionParameter(trader, address(USDC), address(USDCe), 100, 100, 100);

        vm.prank(trader);
        router.mintV3Position(mintParams);

        (,,,,,,, uint128 start_Liquidity,,,,) =
            INonfungiblePositionManager(address(uniswapV3PositionManager)).positions(POSITION_ID);

        // check the position was minted with liquidity
        assertTrue(start_Liquidity > 0);

        // now we roll the fork forward
        vm.rollFork(BLOCK_NUMBER + 10_000);

        INonfungiblePositionManager.IncreaseLiquidityParams memory increaseParams =
            INonfungiblePositionManager.IncreaseLiquidityParams(POSITION_ID, 100, 100, 0, 0, _mockTimestamp());

        vm.prank(trader);
        router.increaseV3PositionLiquidity(increaseParams);

        (,,,,,,, uint128 end_Liquidity,,,,) =
            INonfungiblePositionManager(address(uniswapV3PositionManager)).positions(POSITION_ID);
        assertTrue(end_Liquidity > start_Liquidity);
    }

    // Nothing being collected since no fees have been accrued
    function test_collect() public invariants withApprovals {
        INonfungiblePositionManager.MintParams memory mintParams =
            _mintPositionParameter(trader, address(USDC), address(USDCe), 100, 100, 100);

        vm.prank(trader);
        router.mintV3Position(mintParams);

        INonfungiblePositionManager.CollectParams memory collectParams =
            INonfungiblePositionManager.CollectParams(POSITION_ID, trader, 10, 10);

        vm.prank(trader);
        router.collectV3TokensOwed(collectParams);
    }

    function test_swap(uint256 amountIn, uint256 amountOutMin) public invariants withApprovals {
        vm.assume(amountIn > 10);
        vm.assume(amountIn < BIG_NUMBER);
        vm.assume(amountOutMin < amountIn);

        uint256 start_tokenInBalance = USDC.balanceOf(trader);
        uint256 start_tokenOutBalance = USDCe.balanceOf(trader);

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams(
            address(USDC), address(USDCe), 100, trader, _mockTimestamp(), amountIn, amountOutMin, 0
        );

        vm.prank(trader);
        router.swapTokenWithV3(swapParams);

        uint256 end_tokenInBalance = USDC.balanceOf(trader);
        uint256 end_tokenOutBalance = USDCe.balanceOf(trader);

        assertTrue(end_tokenInBalance < start_tokenInBalance);
        assertTrue(end_tokenOutBalance > start_tokenOutBalance);
    }
}
