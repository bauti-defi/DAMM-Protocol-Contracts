// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {INonfungiblePositionManager} from "@src/interfaces/external/INonfungiblePositionManager.sol";

interface IUniswapV3PositionRouter {
    function uniswapV3PositionManager() external view returns (INonfungiblePositionManager);

    function mintPosition(INonfungiblePositionManager.MintParams calldata params)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function collectTokensOwed(INonfungiblePositionManager.CollectParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1);

    function increasePositionLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
        external
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    function decreasePositionLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1);
}
