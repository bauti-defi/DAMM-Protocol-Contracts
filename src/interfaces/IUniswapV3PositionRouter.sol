// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";

interface IUniswapV3PositionRouter {
    function uniswapV3PositionManager() external view returns (INonfungiblePositionManager);

    function mintV3Position(INonfungiblePositionManager.MintParams calldata params) external payable;

    function collectV3TokensOwed(INonfungiblePositionManager.CollectParams calldata params) external payable;

    function increaseV3PositionLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
        external
        payable;

    function decreaseV3PositionLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external
        payable;
}
