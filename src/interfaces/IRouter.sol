// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";

interface IRouter {
    error InvalidRecipient();
    error TokenNotWhitelisted();

    function uniswapV3PositionManager() external view returns (INonfungiblePositionManager);

    function uniswapV3SwapRouter() external view returns (ISwapRouter);

    function tokenWhitelist(address) external view returns (address);

    function owner() external view returns (address);

    function isTokenWhitelisted(address token) external view returns (bool);

    function swapTokenWithV3(ISwapRouter.ExactInputSingleParams memory params) external;

    function mintV3Position(INonfungiblePositionManager.MintParams calldata params) external;

    function collectV3TokensOwed(INonfungiblePositionManager.CollectParams calldata params) external;

    function increaseV3PositionLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
        external;

    function decreaseV3PositionLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external;

    function supplyAAVE(address token, uint256 amount) external;

    function withdrawAAVE(address asset, uint256 amount) external;
}
