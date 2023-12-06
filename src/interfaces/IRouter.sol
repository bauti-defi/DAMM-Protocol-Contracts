// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";

interface IRouter {
    error CallerMustBeReceiptient();
    
    function uniswapV3PositionManager() external view returns (INonfungiblePositionManager);

    function mintV3Position(INonfungiblePositionManager.MintParams calldata params) external;

    function burnV3Position(uint256 tokenId) external;

    function collectV3TokensOwed(INonfungiblePositionManager.CollectParams calldata params) external;

    function increaseV3PositionLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
        external;

    function decreaseV3PositionLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external;

}
