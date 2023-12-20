// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {IUniswapV3MintCallback} from "@src/interfaces/IUniswapV3MintCallback.sol";

interface IUniswapV3PositionRouter is IUniswapV3MintCallback {

    struct Position {
        // pool address for position
        address pool;
        // the liquidity of the position
        uint128 liquidity;
        // the fee growth of the aggregate position as of the last action on the individual position
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        // how many uncollected tokens are owed to the position, as of the last computation
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    function uniswapV3Factory() external view returns (address);

    function mintLiquidity(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external payable returns(uint256 amount0, uint256 amount1);

    function burnLiquidity(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower, 
        int24 tickUpper, 
        uint128 amount,
        uint256 amountMin0,
        uint256 amountMin1
    ) external returns(uint256 amount0, uint256 amount1);

    function collect(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower, 
        int24 tickUpper, 
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

}
