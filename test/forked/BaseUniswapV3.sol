// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {Test} from "@forge-std/Test.sol";
import {INonfungiblePositionManager} from "@src/interfaces/external/INonfungiblePositionManager.sol";
import {IUniswapRouter} from "@src/interfaces/external/IUniswapRouter.sol";

abstract contract BaseUniswapV3 is Test {
    address public immutable UNI_V3_POSITION_MANAGER_ADDRESS =
        0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    address public immutable UNI_V3_SWAP_ROUTER_ADDRESS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    INonfungiblePositionManager public immutable uniswapPositionManager =
        INonfungiblePositionManager(UNI_V3_POSITION_MANAGER_ADDRESS);

    IUniswapRouter public immutable uniswapRouter = IUniswapRouter(UNI_V3_SWAP_ROUTER_ADDRESS);

    function setUp() public virtual {
        vm.label(UNI_V3_POSITION_MANAGER_ADDRESS, "UNI_V3_POSITION_MANAGER");
        vm.label(UNI_V3_SWAP_ROUTER_ADDRESS, "UNI_V3_SWAP_ROUTER");
    }
}
