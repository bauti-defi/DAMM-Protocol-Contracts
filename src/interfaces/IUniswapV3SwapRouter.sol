// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {ISwapRouter} from "@src/interfaces/external/ISwapRouter.sol";

interface IUniswapV3SwapRouter {
    function uniswapV3SwapRouter() external view returns (ISwapRouter);

    function swapToken(ISwapRouter.ExactInputSingleParams memory params) external returns (uint256 amountOut);
}
