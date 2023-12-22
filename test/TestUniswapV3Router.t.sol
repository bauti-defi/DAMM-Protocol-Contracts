// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";

import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";
import {UniswapV3PositionRouter} from "@src/routers/UniswapV3PositionRouter.sol";
import {TokenWhitelistRegistry} from "@src/base/TokenWhitelistRegistry.sol";

import {BaseUniswap} from "@test/base/BaseUniswap.sol";
import {TokenMinter} from "@test/base/TokenMinter.sol";

import {UniswapTestHelper} from "@test/utils/UniswapTestHelper.sol";

import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";

contract TestUniswapV3Router is BaseUniswap, TokenMinter, UniswapTestHelper {
    uint256 constant BIG_NUMBER = 10 ** 8;

    address public deployer;
    address public trader;
    UniswapV3PositionRouter public router;
    TokenWhitelistRegistry public tokenWhitelistRegistry;

    constructor() UniswapTestHelper(uniswapV3SwapRouter, uniswapV3PositionManager) {}

    function setUp() public override(BaseUniswap, TokenMinter) {
        super.setUp();

        address pool = address(_getPool(address(USDC), address(USDCe), 100));
        vm.label(pool, "UniswapPool");

        deployer = makeAddr("DEPLOYER");
        trader = makeAddr("TRADER");

        vm.startPrank(deployer);
        tokenWhitelistRegistry = new TokenWhitelistRegistry();
        router =
            new UniswapV3PositionRouter(deployer, address(tokenWhitelistRegistry), address(uniswapV3PositionManager));
        vm.stopPrank();

        vm.label(address(router), "ROUTER");
        vm.label(address(tokenWhitelistRegistry), "TOKEN_WHITELIST_REGISTRY");

        assertEq(router.owner(), deployer);
        assertEq(address(router.uniswapV3PositionManager()), address(uniswapV3PositionManager));
        assertEq(USDC.balanceOf(address(router)), 0);
        assertEq(USDCe.balanceOf(address(router)), 0);

        // should not be whitelisted yet
        assertFalse(router.isTokenWhitelisted(trader, address(USDC)));
        assertFalse(router.isTokenWhitelisted(trader, address(USDCe)));

        address[] memory tokenWhitelist = new address[](2);
        tokenWhitelist[0] = address(USDC);
        tokenWhitelist[1] = address(USDCe);

        address[] memory routerWhitelist = new address[](2);
        routerWhitelist[0] = address(router);
        routerWhitelist[1] = address(router);

        vm.prank(trader);
        tokenWhitelistRegistry.whitelistTokens(routerWhitelist, tokenWhitelist);

        assertTrue(tokenWhitelistRegistry.isTokenWhitelisted(trader, address(router), address(USDC)));
        assertTrue(tokenWhitelistRegistry.isTokenWhitelisted(trader, address(router), address(USDCe)));

        // give trader tokens
        mintUSDC(trader, BIG_NUMBER);
        mintUSDCe(trader, BIG_NUMBER);
    }

    modifier withApprovals() {
        vm.startPrank(trader);
        USDC.approve(address(router), type(uint256).max);
        USDCe.approve(address(router), type(uint256).max);
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
            _mintPositionParameter(trader, address(USDC), address(USDCe), 100, BIG_NUMBER / 2, BIG_NUMBER / 2);

        vm.prank(trader);
        router.mintV3Position(mintParams);

        // lets do some swaps
        {
            address swapper = makeAddr("SWAPPER");

            // give swapper tokens
            mintUSDC(swapper, BIG_NUMBER * 100);
            mintUSDCe(swapper, BIG_NUMBER * 100);

            // approve router to spend swapper tokens
            vm.startPrank(swapper);
            USDC.approve(address(uniswapV3SwapRouter), type(uint256).max);
            USDCe.approve(address(uniswapV3SwapRouter), type(uint256).max);
            vm.stopPrank();

            // swap back and fourth
            for (uint256 i = 0; i < 100; i++) {
                address tokenIn = (i % 2 == 0) ? address(USDC) : address(USDCe);
                address tokenOut = (i % 2 == 0) ? address(USDCe) : address(USDC);

                ISwapRouter.ExactInputSingleParams memory swapParams =
                    ISwapRouter.ExactInputSingleParams(tokenIn, tokenOut, 100, swapper, _mockTimestamp(), 10000, 0, 0);

                vm.prank(swapper);
                uniswapV3SwapRouter.exactInputSingle(swapParams);
            }
        }

        INonfungiblePositionManager.CollectParams memory collectParams =
            INonfungiblePositionManager.CollectParams(POSITION_ID, trader, 1000, 1000);

        vm.prank(trader);
        router.collectV3TokensOwed(collectParams);
    }
}
