// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";

interface IUniswapV3Router {
    function uniswapV3PositionManager() external view returns (INonfungiblePositionManager);

    function uniswapV3SwapRouter() external view returns (ISwapRouter);

    function swapTokenWithV3(ISwapRouter.ExactInputSingleParams memory params) external payable;

    function mintV3Position(INonfungiblePositionManager.MintParams calldata params) external payable;

    function collectV3TokensOwed(INonfungiblePositionManager.CollectParams calldata params) external payable;

    function increaseV3PositionLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
        external
        payable;

    function decreaseV3PositionLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external
        payable;
}
