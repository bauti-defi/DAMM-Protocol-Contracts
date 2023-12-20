// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;

import {Test} from "@forge-std/Test.sol";

import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";

abstract contract BaseUniswap is Test {
    // Arbitrum
    address constant UNISWAP_V3_SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address public uniswapV3Factory;

    ISwapRouter public constant uniswapV3SwapRouter = ISwapRouter(UNISWAP_V3_SWAP_ROUTER);

    function setUp() public virtual {
        vm.label(address(uniswapV3SwapRouter), "UniswapV3SwapRouter");

        uniswapV3Factory = uniswapV3SwapRouter.factory();
        vm.label(uniswapV3Factory, "UniswapV3Factory");
    }
}
