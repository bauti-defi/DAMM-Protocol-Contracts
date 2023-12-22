// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";

interface IUniswapV3SwapRouter {
    function uniswapV3SwapRouter() external view returns (ISwapRouter);

    function swapToken(ISwapRouter.ExactInputSingleParams memory params) external payable;
}
