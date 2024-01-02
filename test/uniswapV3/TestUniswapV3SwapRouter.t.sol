// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {Test, console2} from "@forge-std/Test.sol";
import {IBaseUniswapV3} from "@test/uniswapV3/IBaseUniswapV3.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";
import {IWETH9} from "@src/interfaces/external/IWETH9.sol";
import {TickMath} from "@test/utils/TickMath.sol";
import {TokenWhitelistRegistry} from "@src/base/TokenWhitelistRegistry.sol";
import {UniswapV3SwapRouter} from "@src/routers/UniswapV3SwapRouter.sol";
import {ISwapRouter} from "@src/interfaces/external/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@src/interfaces/external/INonfungiblePositionManager.sol";
import {IUniswapV3PoolActions} from "@src/interfaces/external/IUniswapV3PoolActions.sol";
import {IUniswapV3PoolState} from "@src/interfaces/external/IUniswapV3PoolState.sol";
import {IRouter} from "@src/interfaces/IRouter.sol";
import {BaseMulticallerWithSender} from "@test/base/BaseMulticallerWithSender.sol";

contract TestUniswapV3SwapRouter is Test, BaseMulticallerWithSender {
    struct MintCallbackData {
        address token0;
        address token1;
        address payer;
    }

    uint256 private constant ONE_MILLION = 1_000_000;
    uint256 private constant ONE_BILLION = ONE_MILLION * 1000;
    uint24 private constant POOL_FEE = 500;

    IBaseUniswapV3 public uniswapV3;
    MockERC20 public token0;
    MockERC20 public token1;
    IWETH9 public weth9;
    address public pool;
    TokenWhitelistRegistry public tokenWhitelistRegistry;
    UniswapV3SwapRouter public dammRouter;

    int24 startTick;
    address public vault;
    address public trader;
    address public lp;

    function setUp() public override(BaseMulticallerWithSender) {
        super.setUp();

        trader = makeAddr("Trader");
        lp = makeAddr("LP");
        vault = makeAddr("Vault");

        uniswapV3 = _deployUniswapV3();

        token0 = new MockERC20();
        token1 = new MockERC20();

        // mint tokens to vault
        token0.mint(vault, ONE_MILLION);
        token1.mint(vault, ONE_MILLION);

        // mint tokens to LP
        token0.mint(lp, ONE_BILLION);
        token1.mint(lp, ONE_BILLION);

        //deploy pool
        pool = uniswapV3.deployPool(address(token0), address(token1), POOL_FEE);

        // deploy token whitelist registry
        tokenWhitelistRegistry = new TokenWhitelistRegistry();

        vm.label(address(tokenWhitelistRegistry), "TokenWhitelistRegistry");

        // deploy damm uniswap v3 swap router
        dammRouter = new UniswapV3SwapRouter(
            address(this),
            uniswapV3.weth9(),
            address(tokenWhitelistRegistry),
            address(multicallerWithSender),
            uniswapV3.localUniV3Router()
        );

        vm.label(address(dammRouter), "DammRouter");

        vm.startPrank(vault);
        // add tokens to whitelist
        tokenWhitelistRegistry.whitelistToken(address(dammRouter), address(token0));
        tokenWhitelistRegistry.whitelistToken(address(dammRouter), address(token1));

        // approve allowance to router
        token0.approve(address(dammRouter), type(uint256).max);
        token1.approve(address(dammRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(lp);
        // approve this contract to spend
        token0.approve(address(this), type(uint256).max);
        token1.approve(address(this), type(uint256).max);
        vm.stopPrank();

        startTick = 0;

        // initialize pool
        uniswapV3.initializePool(pool, startTick);

        // add liquidity to pool by calling it directly
        (bool success,) = pool.call(
            abi.encodeWithSelector(
                bytes4(keccak256("mint(address,int24,int24,uint128,bytes)")),
                lp,
                startTick - 500,
                startTick + 500,
                100_000_000,
                abi.encode(MintCallbackData({token0: address(token0), token1: address(token1), payer: lp}))
            )
        );

        require(success, "mint failed");
    }

    /// @notice Called to `msg.sender` after minting liquidity to a position from IUniswapV3Pool#mint.
    /// @dev In the implementation you must pay the pool tokens owed for the minted liquidity.
    /// The caller of this method must be checked to be a UniswapV3Pool deployed by the canonical UniswapV3Factory.
    /// @param amount0Owed The amount of token0 due to the pool for the minted liquidity
    /// @param amount1Owed The amount of token1 due to the pool for the minted liquidity
    /// @param data Any data passed through by the caller via the IUniswapV3PoolActions#mint call
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external {
        MintCallbackData memory mintCallback = abi.decode(data, (MintCallbackData));

        if (amount0Owed > 0) token0.transferFrom(mintCallback.payer, address(pool), amount0Owed);
        if (amount1Owed > 0) token1.transferFrom(mintCallback.payer, address(pool), amount1Owed);
    }

    function _deployUniswapV3() internal returns (IBaseUniswapV3) {
        bytes memory bytecode = abi.encodePacked(vm.getCode("LocalUniswapV3Deployer.sol:Deployer"));
        address deployer;
        assembly {
            deployer := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        return IBaseUniswapV3(deployer);
    }

    modifier invariants() {
        // damm router should never end up with any funds
        assertEq(token0.balanceOf(address(dammRouter)), 0);
        assertEq(token1.balanceOf(address(dammRouter)), 0);
        _;
        assertEq(token0.balanceOf(address(dammRouter)), 0);
        assertEq(token1.balanceOf(address(dammRouter)), 0);
    }

    modifier withTokens(address t0, address t1) {
        token0 = MockERC20(t0);
        token1 = MockERC20(t1);

        // make they are order the right way
        if (address(token0) > address(token1)) (token0, token1) = (token1, token0);

        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");
        _;
    }

    function test_swap(uint256 amount, bool zeroForOne)
        public
        withTokens(address(token0), address(token1))
        invariants
    {
        vm.assume(amount > 0);
        vm.assume(amount < ONE_MILLION);

        // default: token1 for token0
        address tokenIn = address(token1);
        address tokenOut = address(token0);

        if (zeroForOne) (tokenIn, tokenOut) = (address(token0), address(token1));

        vm.prank(vault);
        uint256 amountOut = dammRouter.swapToken(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: POOL_FEE,
                recipient: vault,
                deadline: block.timestamp + 10_000,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        assertEq(ONE_MILLION + amountOut, MockERC20(tokenOut).balanceOf(vault));
        assertEq(ONE_MILLION - amount, MockERC20(tokenIn).balanceOf(vault));
    }

    function test_cannot_swap_unauthorized_token0(address token, bool zeroForOne)
        public
        withTokens(address(token0), address(token1))
        invariants
    {
        vm.assume(token != address(token0));
        vm.assume(token != address(token1));

        // default: token1 for token0
        address tokenIn = address(token1);
        address tokenOut = address(token);

        if (zeroForOne) (tokenIn, tokenOut) = (address(token), address(token1));

        vm.prank(vault);
        vm.expectRevert(IRouter.TokenNotWhitelisted.selector);
        dammRouter.swapToken(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: POOL_FEE,
                recipient: vault,
                deadline: block.timestamp + 10_000,
                amountIn: 100,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function test_cannot_swap_unauthorized_token1(address token, bool zeroForOne)
        public
        withTokens(address(token0), address(token1))
        invariants
    {
        vm.assume(token != address(token1));
        vm.assume(token != address(token0));

        // default: token1 for token0
        address tokenIn = address(token);
        address tokenOut = address(token0);

        if (zeroForOne) (tokenIn, tokenOut) = (address(token0), address(token));

        vm.prank(vault);
        vm.expectRevert(IRouter.TokenNotWhitelisted.selector);
        dammRouter.swapToken(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: POOL_FEE,
                recipient: vault,
                deadline: block.timestamp + 10_000,
                amountIn: 100,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }
}
