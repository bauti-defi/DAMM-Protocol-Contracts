// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {IUniswapV3PoolState} from "@src/interfaces/IUniswapV3PoolState.sol";
import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@test/utils/PoolAddress.sol";
import {console2} from "@forge-std/console2.sol";

contract UniswapTestHelper {
    // this id is hardcoded because it depends on what block the chain is forked.
    // We are assuming arbitrum mainnet @ block 124240758 for this test
    uint256 public POSITION_ID = 788510;
    uint256 public BLOCK_NUMBER = 124_240_758;

    ISwapRouter private uniswapV3SwapRouter;
    INonfungiblePositionManager private uniswapV3PositionManager;

    constructor(ISwapRouter _uniswapV3SwapRouter, INonfungiblePositionManager _uniswapV3PositionManager) {
        uniswapV3SwapRouter = _uniswapV3SwapRouter;
        uniswapV3PositionManager = _uniswapV3PositionManager;
    }

    /// @dev Returns the pool for the given token pair and fee. The pool contract may or may not exist.
    function _getPool(address tokenA, address tokenB, uint24 fee) internal view returns (IUniswapV3PoolState) {
        return IUniswapV3PoolState(
            PoolAddress.computeAddress(
                address(uniswapV3SwapRouter.factory()), PoolAddress.getPoolKey(tokenA, tokenB, fee)
            )
        );
    }

    function _getSqrtPriceX96(address tokenA, address tokenB, uint24 fee)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        (sqrtPriceX96,,,,,,) = _getPool(tokenA, tokenB, fee).slot0();
    }

    function _getCurrentTick(address tokenA, address tokenB, uint24 fee) internal view returns (int24 currentTick) {
        (, currentTick,,,,,) = _getPool(tokenA, tokenB, fee).slot0();
    }

    function _logCurrentTick(address tokenA, address tokenB, uint24 fee) internal view {
        console2.logInt(_getCurrentTick(tokenA, tokenB, fee));
    }

    function _mockTimestamp() internal view returns (uint256) {
        return block.timestamp + 5000;
    }

    function _logPosition(uint256 tokenId) internal view {
        (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = INonfungiblePositionManager(address(uniswapV3PositionManager)).positions(tokenId);

        console2.logUint(nonce);
        console2.logAddress(operator);
        console2.logAddress(token0);
        console2.logAddress(token1);
        console2.logUint(fee);
        console2.logInt(tickLower);
        console2.logInt(tickUpper);
        console2.logUint(liquidity);
        console2.logUint(feeGrowthInside0LastX128);
        console2.logUint(feeGrowthInside1LastX128);
        console2.logUint(tokensOwed0);
        console2.logUint(tokensOwed1);
    }

    function _mintPositionParameter(
        address recipient,
        address token0,
        address token1,
        uint24 fee,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal view returns (INonfungiblePositionManager.MintParams memory params) {
        int24 currentTick = _getCurrentTick(token0, token1, fee);
        int24 tickerLower = currentTick - 1;
        int24 tickerUpper = currentTick + 1;

        // @dev default amount0Min and amount1Min to 0
        params = INonfungiblePositionManager.MintParams(
            token0,
            token1,
            fee,
            tickerLower,
            tickerUpper,
            amount0Desired,
            amount1Desired,
            0,
            0,
            recipient,
            _mockTimestamp()
        );
    }

    function _getUniV3PositionCount(address owner) internal view returns (uint256) {
        return IERC721(address(uniswapV3PositionManager)).balanceOf(owner);
    }
}
