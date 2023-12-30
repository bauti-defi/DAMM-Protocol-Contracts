// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {INonfungiblePositionManager} from "@src/interfaces/external/INonfungiblePositionManager.sol";

interface IUniswapV3PositionRouter {
    function uniswapV3PositionManager() external view returns (INonfungiblePositionManager);

    function mintPosition(INonfungiblePositionManager.MintParams calldata params) external payable;

    function collectTokensOwed(INonfungiblePositionManager.CollectParams calldata params) external payable;

    function increasePositionLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
        external
        payable;

    function decreasePositionLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external
        payable;
}
