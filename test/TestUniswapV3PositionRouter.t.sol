// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import {Test} from "@forge-std/Test.sol";

import {BaseUniswap} from "@test/base/BaseUniswap.sol";
import {TokenMinter} from "@test/base/TokenMinter.sol";
import {UniswapV3PositionRouter} from "@src/routers/UniswapV3PositionRouter.sol";
import {TokenWhitelistRegistry} from "@src/base/TokenWhitelistRegistry.sol";
import {PoolAddress} from "@src/lib/PoolAddress.sol";
import {IUniswapV3PoolState} from "@src/interfaces/IUniswapV3PoolState.sol";
import {console2} from "@forge-std/console2.sol";
import {IRouter} from "@src/interfaces/IRouter.sol";

contract TestUniswapV3PositionRouter is Test, TokenMinter, BaseUniswap {
    using PoolAddress for address;

    uint256 constant ONE_MILLION = 1_000_000;

    address public caller;
    address public deployer;

    UniswapV3PositionRouter public router;
    TokenWhitelistRegistry public tokenWhitelistRegistry;

    address public pool;
    address public token0;
    address public token1;
    uint24 public fee = 500;

    modifier invariants() {
        assertEq(USDC.balanceOf(address(router)), 0);
        assertEq(USDCe.balanceOf(address(router)), 0);
        _;
        assertEq(USDC.balanceOf(address(router)), 0);
        assertEq(USDCe.balanceOf(address(router)), 0);
    }

    function setUp() public override(TokenMinter, BaseUniswap) {
        TokenMinter.setUp();
        BaseUniswap.setUp();

        deployer = makeAddr("Deployer");

        vm.startPrank(deployer);
        tokenWhitelistRegistry = new TokenWhitelistRegistry();
        router = new UniswapV3PositionRouter(deployer, address(tokenWhitelistRegistry), uniswapV3Factory);
        vm.stopPrank();

        caller = makeAddr("Caller");

        mintUSDC(caller, ONE_MILLION);
        mintUSDCe(caller, ONE_MILLION);
        mintDAI(caller, ONE_MILLION);

        vm.startPrank(caller);
        tokenWhitelistRegistry.whitelistToken(address(router), ARB_USDC);
        tokenWhitelistRegistry.whitelistToken(address(router), ARB_USDCe);

        /// @notice we don't whitelist DAI to test against unwhitelisted tokens

        USDC.approve(address(router), type(uint256).max);
        USDCe.approve(address(router), type(uint256).max);
        DAI.approve(address(router), type(uint256).max);
        vm.stopPrank();

        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(ARB_USDC, ARB_USDCe, fee);
        token0 = poolKey.token0;
        token1 = poolKey.token1;
        pool = uniswapV3Factory.computeAddress(poolKey);
        vm.label(pool, "USDC/USDCe Pool");
    }

    function test_mint() public invariants {
        uint256 poolBalance0_start = USDC.balanceOf(pool);
        uint256 poolBalance1_start = USDCe.balanceOf(pool);

        vm.prank(caller);
        router.mintLiquidity(token0, token1, fee, -10, 10, 10_000);

        uint256 callerBalance0_end = USDC.balanceOf(caller);
        uint256 callerBalance1_end = USDCe.balanceOf(caller);
        uint256 poolBalance0_end = USDC.balanceOf(pool);
        uint256 poolBalance1_end = USDCe.balanceOf(pool);

        assertEq(poolBalance0_end - poolBalance0_start, ONE_MILLION - callerBalance0_end);
        assertEq(poolBalance1_end - poolBalance1_start, ONE_MILLION - callerBalance1_end);
    }

    function test_cannot_mint_with_unwhitelisted_token() public invariants {
        uint256 callerBalance0_start = USDC.balanceOf(caller);
        uint256 callerBalance1_start = DAI.balanceOf(caller);

        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(ARB_USDC, ARB_DAI, fee);
        token0 = poolKey.token0;
        token1 = poolKey.token1;
        pool = uniswapV3Factory.computeAddress(poolKey);
        vm.label(pool, "USDC/DAI Pool");

        vm.prank(caller);
        vm.expectRevert(IRouter.TokenNotWhitelisted.selector);
        router.mintLiquidity(token0, token1, fee, -10, 10, 10_000);

        assertEq(callerBalance0_start, USDC.balanceOf(caller));
        assertEq(callerBalance1_start, DAI.balanceOf(caller));
    }

    function test_burn() public invariants {
        uint256 poolBalance0_start = USDC.balanceOf(pool);
        uint256 poolBalance1_start = USDCe.balanceOf(pool);

        vm.prank(caller);
        router.mintLiquidity(token0, token1, fee, -10, 10, 10_000);

        uint256 callerBalance0_start = USDC.balanceOf(caller);
        uint256 callerBalance1_start = USDCe.balanceOf(caller);

        vm.prank(caller);
        router.burnLiquidity(token0, token1, fee, -10, 10, 10_000, 0, 0);

        uint256 callerBalance0_end = USDC.balanceOf(caller);
        uint256 callerBalance1_end = USDCe.balanceOf(caller);
        uint256 poolBalance0_end = USDC.balanceOf(pool);
        uint256 poolBalance1_end = USDCe.balanceOf(pool);

        // assertEq(poolBalance0_end - poolBalance0_start, callerBalance0_start - callerBalance0_end);
        // assertEq(poolBalance1_end - poolBalance1_start, callerBalance1_start - callerBalance1_end);
    }
}
