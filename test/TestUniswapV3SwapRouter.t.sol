// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";

import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";
import {UniswapV3SwapRouter} from "@src/routers/UniswapV3SwapRouter.sol";
import {TokenWhitelistRegistry} from "@src/base/TokenWhitelistRegistry.sol";

import {BaseUniswap} from "@test/base/BaseUniswap.sol";
import {TokenMinter} from "@test/base/TokenMinter.sol";

import {UniswapTestHelper} from "@test/utils/UniswapTestHelper.sol";

import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";

contract TestUniswapV3SwapRouter is BaseUniswap, TokenMinter, UniswapTestHelper {
    uint256 constant BIG_NUMBER = 10 ** 8;

    address public deployer;
    address public trader;
    UniswapV3SwapRouter public router;
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
        router = new UniswapV3SwapRouter(deployer, address(tokenWhitelistRegistry), address(uniswapV3SwapRouter));
        vm.stopPrank();

        vm.label(address(router), "ROUTER");
        vm.label(address(tokenWhitelistRegistry), "TOKEN_WHITELIST_REGISTRY");

        assertEq(router.owner(), deployer);
        assertEq(address(router.uniswapV3SwapRouter()), address(uniswapV3SwapRouter));
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

    function test_swap(uint256 amountIn, uint256 amountOutMin) public invariants withApprovals {
        vm.assume(amountIn > 1000);
        vm.assume(amountIn < BIG_NUMBER);
        vm.assume(amountOutMin < amountIn);

        uint256 start_tokenInBalance = USDC.balanceOf(trader);
        uint256 start_tokenOutBalance = USDCe.balanceOf(trader);

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams(
            address(USDC), address(USDCe), 100, trader, _mockTimestamp(), amountIn, amountOutMin, 0
        );

        vm.prank(trader);
        router.swapToken(swapParams);

        uint256 end_tokenInBalance = USDC.balanceOf(trader);
        uint256 end_tokenOutBalance = USDCe.balanceOf(trader);

        assertTrue(end_tokenInBalance < start_tokenInBalance);
        assertTrue(end_tokenOutBalance > start_tokenOutBalance);
    }

    // create 5 swaps with different amounts, store them in a bytes[] and then call multicall
    function test_multicall() public invariants withApprovals {
        uint256 start_tokenInBalance = USDC.balanceOf(trader);
        uint256 start_tokenOutBalance = USDCe.balanceOf(trader);

        uint256[] memory amountsIn = new uint256[](5);

        amountsIn[0] = 1000;
        amountsIn[1] = 2000;
        amountsIn[2] = 3000;
        amountsIn[3] = 4000;
        amountsIn[4] = 5000;

        bytes[] memory data = new bytes[](5);

        for (uint256 i = 0; i < 5; i++) {
            ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams(
                address(USDC), address(USDCe), 100, trader, _mockTimestamp(), amountsIn[i], 0, 0
            );

            data[i] = abi.encodeWithSelector(UniswapV3SwapRouter.swapToken.selector, swapParams);
        }

        vm.prank(trader);
        router.multicall(data);

        uint256 end_tokenInBalance = USDC.balanceOf(trader);
        uint256 end_tokenOutBalance = USDCe.balanceOf(trader);

        assertTrue(end_tokenInBalance < start_tokenInBalance);
        assertTrue(end_tokenOutBalance > start_tokenOutBalance);
    }
}
