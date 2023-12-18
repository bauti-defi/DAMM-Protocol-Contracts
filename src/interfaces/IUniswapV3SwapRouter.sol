// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";

interface IUniswapV3SwapRouter {
    function uniswapV3SwapRouter() external view returns (ISwapRouter);

    function swapTokenWithV3(ISwapRouter.ExactInputSingleParams memory params) external payable;
}
