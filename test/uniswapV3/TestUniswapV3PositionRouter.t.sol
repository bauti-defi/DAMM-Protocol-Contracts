// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {BaseMulticallerWithSender} from "@test/base/BaseMulticallerWithSender.sol";
import {BaseUniswapV3} from "@test/base/uniswapV3/BaseUniswapV3.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";
import {TokenWhitelistRegistry} from "@src/base/TokenWhitelistRegistry.sol";
import {UniswapV3PositionRouter} from "@src/routers/UniswapV3PositionRouter.sol";
import {INonfungiblePositionManager} from "@src/interfaces/external/INonfungiblePositionManager.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";
import {IRouter} from "@src/interfaces/IRouter.sol";

contract TestUniswapV3PositionRouter is BaseUniswapV3, BaseMulticallerWithSender {
    uint256 private constant ONE_BILLION = 1_000_000 * 1000;
    uint24 private constant POOL_FEE = 500;

    int24 private constant START_TICK = 0;

    MockERC20 public authorizedToken0;
    MockERC20 public authorizedToken1;
    MockERC20 public unauthorizedToken;

    MockERC20 public token0;
    MockERC20 public token1;

    address public lp;
    address public otherLP;
    address public pool;
    address public unauthorizedPool0;

    TokenWhitelistRegistry public tokenWhitelistRegistry;
    UniswapV3PositionRouter public dammRouter;

    function setUp() public override(BaseUniswapV3, BaseMulticallerWithSender) {
        BaseUniswapV3.setUp();
        BaseMulticallerWithSender.setUp();

        lp = makeAddr("LP");
        otherLP = makeAddr("otherLP");

        authorizedToken0 = new MockERC20();
        authorizedToken1 = new MockERC20();
        unauthorizedToken = new MockERC20();

        // mint tokens to LP
        authorizedToken0.mint(lp, ONE_BILLION);
        authorizedToken0.mint(otherLP, ONE_BILLION);
        authorizedToken1.mint(lp, ONE_BILLION);
        authorizedToken1.mint(otherLP, ONE_BILLION);
        unauthorizedToken.mint(lp, ONE_BILLION);
        unauthorizedToken.mint(otherLP, ONE_BILLION);

        //deploy pools
        pool = uniswapV3.deployPool(address(authorizedToken0), address(authorizedToken1), POOL_FEE);
        unauthorizedPool0 = uniswapV3.deployPool(address(unauthorizedToken), address(authorizedToken1), POOL_FEE);

        // initialize pools
        uniswapV3.initializePool(pool, START_TICK);
        uniswapV3.initializePool(unauthorizedPool0, START_TICK);

        // deploy token whitelist registry
        tokenWhitelistRegistry = new TokenWhitelistRegistry();
        vm.label(address(tokenWhitelistRegistry), "tokenWhitelistRegistry");

        // deploy router
        dammRouter = new UniswapV3PositionRouter(
            address(this),
            uniswapV3.weth9(),
            address(tokenWhitelistRegistry),
            address(multicallerWithSender),
            uniswapV3.localUniV3PM()
        );

        vm.label(address(dammRouter), "DAMM Router");

        vm.startPrank(lp);
        // approve router
        authorizedToken0.approve(address(dammRouter), type(uint256).max);
        authorizedToken1.approve(address(dammRouter), type(uint256).max);
        unauthorizedToken.approve(address(dammRouter), type(uint256).max);
        IERC721(uniswapV3.localUniV3PM()).setApprovalForAll(address(dammRouter), true);

        // whitelist tokens
        tokenWhitelistRegistry.whitelistToken(address(dammRouter), address(authorizedToken0));
        tokenWhitelistRegistry.whitelistToken(address(dammRouter), address(authorizedToken1));
        vm.stopPrank();

        vm.startPrank(otherLP);
        // approve PM
        authorizedToken0.approve(uniswapV3.localUniV3PM(), type(uint256).max);
        authorizedToken1.approve(uniswapV3.localUniV3PM(), type(uint256).max);
        unauthorizedToken.approve(uniswapV3.localUniV3PM(), type(uint256).max);
        IERC721(uniswapV3.localUniV3PM()).setApprovalForAll(address(dammRouter), true);
        vm.stopPrank();
    }

    modifier invariants() {
        // damm router should never end up with any funds
        assertEq(token0.balanceOf(address(dammRouter)), 0);
        assertEq(token1.balanceOf(address(dammRouter)), 0);
        assertEq(IERC721(uniswapV3.localUniV3PM()).balanceOf(address(dammRouter)), 0);
        _;
        assertEq(token0.balanceOf(address(dammRouter)), 0);
        assertEq(token1.balanceOf(address(dammRouter)), 0);
        assertEq(IERC721(uniswapV3.localUniV3PM()).balanceOf(address(dammRouter)), 0);
    }

    modifier useTokens(MockERC20 t0, MockERC20 t1) {
        token0 = t0;
        token1 = t1;

        // make they are order the right way
        if (address(token0) > address(token1)) (token0, token1) = (token1, token0);

        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");
        _;
    }

    function _mint_position_with_PM(address minter, uint256 amount0Desired, uint256 amount1Desired)
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        vm.startPrank(minter);
        token0.transfer(uniswapV3.localUniV3PM(), amount0Desired);
        token1.transfer(uniswapV3.localUniV3PM(), amount1Desired);

        (tokenId, liquidity, amount0, amount1) = INonfungiblePositionManager(uniswapV3.localUniV3PM()).mint(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: POOL_FEE,
                tickLower: START_TICK - 500,
                tickUpper: START_TICK + 500,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: minter,
                deadline: block.timestamp + 10000
            })
        );

        vm.stopPrank();
    }

    function _mint_position_with_router(address minter, uint256 amount0Desired, uint256 amount1Desired)
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        vm.prank(minter);
        (tokenId, liquidity, amount0, amount1) = dammRouter.mintPosition(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: POOL_FEE,
                tickLower: START_TICK - 500,
                tickUpper: START_TICK + 500,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: minter,
                deadline: block.timestamp + 10000
            })
        );
    }

    function test_mint_position_with_router() public useTokens(authorizedToken0, authorizedToken1) invariants {
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) =
            _mint_position_with_router(lp, 1000, 1000);

        (
            ,
            address operator,
            address _token0,
            address _token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 _liquidity,
            ,
            ,
            ,
        ) = INonfungiblePositionManager(uniswapV3.localUniV3PM()).positions(tokenId);

        assertEq(operator, address(0));
        assertEq(_token0, address(token0));
        assertEq(_token1, address(token1));
        assertEq(fee, POOL_FEE);
        assertEq(tickLower, START_TICK - 500);
        assertEq(tickUpper, START_TICK + 500);
        assertEq(_liquidity, liquidity);

        assertEq(amount0, 1000);
        assertEq(amount1, 1000);

        assertEq(IERC721(uniswapV3.localUniV3PM()).ownerOf(tokenId), lp);
        assertEq(ONE_BILLION - 1000, token0.balanceOf(lp));
        assertEq(ONE_BILLION - 1000, token1.balanceOf(lp));
    }

    function test_cannot_mint_position_on_behalf_of_other(address other)
        public
        useTokens(authorizedToken0, authorizedToken1)
        invariants
    {
        vm.assume(other != lp);

        vm.prank(lp);
        vm.expectRevert(IRouter.InvalidRecipient.selector);
        dammRouter.mintPosition(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: POOL_FEE,
                tickLower: START_TICK - 500,
                tickUpper: START_TICK + 500,
                amount0Desired: 1000,
                amount1Desired: 1000,
                amount0Min: 0,
                amount1Min: 0,
                recipient: other,
                deadline: block.timestamp + 10000
            })
        );
    }

    function test_cannot_mint_position_with_router_with_unauthorized_token0()
        public
        useTokens(unauthorizedToken, authorizedToken1)
        invariants
    {
        vm.prank(lp);
        vm.expectRevert(IRouter.TokenNotWhitelisted.selector);
        dammRouter.mintPosition(
            INonfungiblePositionManager.MintParams({
                token0: address(unauthorizedToken),
                token1: address(token1),
                fee: POOL_FEE,
                tickLower: START_TICK - 500,
                tickUpper: START_TICK + 500,
                amount0Desired: 1000,
                amount1Desired: 1000,
                amount0Min: 0,
                amount1Min: 0,
                recipient: lp,
                deadline: block.timestamp + 10000
            })
        );
    }

    function test_cannot_mint_position_with_router_with_unauthorized_token1()
        public
        useTokens(authorizedToken0, unauthorizedToken)
        invariants
    {
        vm.prank(lp);
        vm.expectRevert(IRouter.TokenNotWhitelisted.selector);
        dammRouter.mintPosition(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(unauthorizedToken),
                fee: POOL_FEE,
                tickLower: START_TICK - 500,
                tickUpper: START_TICK + 500,
                amount0Desired: 1000,
                amount1Desired: 1000,
                amount0Min: 0,
                amount1Min: 0,
                recipient: lp,
                deadline: block.timestamp + 10000
            })
        );
    }

    function test_increase_liquidity() public useTokens(authorizedToken0, authorizedToken1) invariants {
        (uint256 tokenId, uint128 start_liquidity, uint256 start_amount0, uint256 start_amount1) =
            _mint_position_with_router(lp, 1000, 1000);

        vm.prank(lp);
        (uint128 end_liquidity, uint256 amount0, uint256 amount1) = dammRouter.increasePositionLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: 1000,
                amount1Desired: 1000,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 10000
            })
        );

        (, address operator, address _token0, address _token1, uint24 fee,,, uint128 _liquidity,,,,) =
            INonfungiblePositionManager(uniswapV3.localUniV3PM()).positions(tokenId);

        assertEq(operator, address(0));
        assertEq(_token0, address(token0));
        assertEq(_token1, address(token1));
        assertEq(fee, POOL_FEE);
        assertEq(_liquidity, start_liquidity + end_liquidity);

        assertEq(token0.balanceOf(lp), ONE_BILLION - start_amount0 - amount0);
        assertEq(token1.balanceOf(lp), ONE_BILLION - start_amount1 - amount1);

        assertEq(IERC721(uniswapV3.localUniV3PM()).ownerOf(tokenId), lp);
    }

    function test_can_only_increase_liquidity_of_own_position()
        public
        useTokens(authorizedToken0, authorizedToken1)
        invariants
    {
        _mint_position_with_PM(otherLP, 1000, 1000);

        _mint_position_with_router(lp, 1000, 1000);

        vm.prank(lp);
        vm.expectRevert(IRouter.InvalidRecipient.selector);
        dammRouter.increasePositionLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: 1, // this is the otherLP's position
                amount0Desired: 1000,
                amount1Desired: 1000,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 10000
            })
        );
    }

    function test_cannot_increase_liquidity_of_null_position() public useTokens(authorizedToken0, authorizedToken1) {
        vm.prank(lp);
        vm.expectRevert("ERC721: owner query for nonexistent token");
        dammRouter.increasePositionLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: 1, // this position does not exist because none have been minted
                amount0Desired: 1000,
                amount1Desired: 1000,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 10000
            })
        );
    }

    function test_decrease_liquidity() public useTokens(authorizedToken0, authorizedToken1) invariants {
        (uint256 tokenId, uint128 start_liquidity, uint256 start_amount0, uint256 start_amount1) =
            _mint_position_with_router(lp, 1000, 1000);

        vm.prank(lp);
        (uint256 amount0, uint256 amount1) = dammRouter.decreasePositionLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: 100,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 10000
            })
        );

        (
            ,
            address operator,
            address _token0,
            address _token1,
            uint24 fee,
            ,
            ,
            uint128 _liquidity,
            ,
            ,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = INonfungiblePositionManager(uniswapV3.localUniV3PM()).positions(tokenId);

        assertEq(operator, address(0));
        assertEq(_token0, address(token0));
        assertEq(_token1, address(token1));
        assertEq(fee, POOL_FEE);
        assertEq(_liquidity, start_liquidity - 100);
        assertEq(tokensOwed0, amount0);
        assertEq(tokensOwed1, amount1);

        assertEq(token0.balanceOf(lp), ONE_BILLION - start_amount0);
        assertEq(token1.balanceOf(lp), ONE_BILLION - start_amount1);
        assertEq(IERC721(uniswapV3.localUniV3PM()).ownerOf(tokenId), lp);
    }

    function test_can_only_decrease_liquidity_of_own_position()
        public
        useTokens(authorizedToken0, authorizedToken1)
        invariants
    {
        _mint_position_with_PM(otherLP, 1000, 1000);

        _mint_position_with_router(lp, 1000, 1000);

        vm.prank(lp);
        vm.expectRevert(IRouter.InvalidRecipient.selector);
        dammRouter.decreasePositionLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: 1, // this is the otherLP's position
                liquidity: 100,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 10000
            })
        );
    }

    function test_cannot_decrease_liquidity_of_null_position() public useTokens(authorizedToken0, authorizedToken1) {
        vm.prank(lp);
        vm.expectRevert("ERC721: owner query for nonexistent token");
        dammRouter.decreasePositionLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: 1, // this position does not exist because none have been minted
                liquidity: 100,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 10000
            })
        );
    }

    function test_collect_tokens_owed() public useTokens(authorizedToken0, authorizedToken1) invariants {
        (uint256 tokenId, uint128 start_liquidity,,) = _mint_position_with_router(lp, 1000, 1000);

        vm.startPrank(lp);
        (uint256 amount0, uint256 amount1) = dammRouter.decreasePositionLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: start_liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 10000
            })
        );

        (uint256 amount0Collected, uint256 amount1Collected) = dammRouter.collectTokensOwed(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: lp,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        vm.stopPrank();

        assertEq(amount0Collected, amount0);
        assertEq(amount1Collected, amount1);

        assertEq(token0.balanceOf(lp), ONE_BILLION - 1); // -1 because of rounding errors from uniswap core
        assertEq(token1.balanceOf(lp), ONE_BILLION - 1); // -1 because of rounding errors from uniswap core
        assertEq(IERC721(uniswapV3.localUniV3PM()).ownerOf(tokenId), lp);
    }

    function test_can_only_collect_tokens_of_own_position()
        public
        useTokens(authorizedToken0, authorizedToken1)
        invariants
    {
        _mint_position_with_PM(otherLP, 1000, 1000);

        _mint_position_with_router(lp, 1000, 1000);

        vm.prank(lp);
        vm.expectRevert(IRouter.InvalidRecipient.selector);
        dammRouter.collectTokensOwed(
            INonfungiblePositionManager.CollectParams({
                tokenId: 1, // this is the otherLP's position
                recipient: lp,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }
}
