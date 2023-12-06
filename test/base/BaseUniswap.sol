// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";

import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";

abstract contract BaseUniswap is Test {
    // Arbitrum
    address constant UNISWAP_V3_SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNISWAP_V3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    ISwapRouter public constant uniswapV3SwapRouter = ISwapRouter(UNISWAP_V3_SWAP_ROUTER);
    INonfungiblePositionManager public constant uniswapV3PositionManager =
        INonfungiblePositionManager(UNISWAP_V3_POSITION_MANAGER);

    function setUp() public virtual {
        vm.label(address(uniswapV3SwapRouter), "uniswapV3SwapRouter");
        vm.label(address(uniswapV3PositionManager), "uniswapV3PositionManager");
    }
}
