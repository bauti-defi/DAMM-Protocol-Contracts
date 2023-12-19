// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IUniswapV3MintCallback} from "@src/interfaces/IUniswapV3MintCallback.sol";

interface IUniswapV3PositionRouter is IUniswapV3MintCallback {
    function uniswapV3Factory() external view returns (address);

    function mintPosition(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external payable;
}
