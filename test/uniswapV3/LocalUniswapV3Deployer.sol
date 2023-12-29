// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6;
pragma abicoder v2;

import {Vm} from "@forge-std/Vm.sol";
import {console2} from "@forge-std/console2.sol";
import {console2} from "@forge-std/console2.sol";
import {UniswapV3Factory} from "@uniswap-v3-core/UniswapV3Factory.sol";
import {IUniswapV3Factory} from "@uniswap-v3-core/interfaces/IUniswapV3Factory.sol";
import {NonfungiblePositionManager} from "@uniswap-v3-periphery/NonfungiblePositionManager.sol";
import {INonfungiblePositionManager} from "@uniswap-v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {SwapRouter} from "@uniswap-v3-periphery/SwapRouter.sol";
import {ISwapRouter} from "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import {IBaseUniswapV3} from "@test/uniswapV3/IBaseUniswapV3.sol";

contract Deployer is IBaseUniswapV3 {
    // Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm internal constant vm = Vm(VM_ADDRESS);

    address public override localUniV3Factory;
    address public override weth9;
    address public override localUniV3TokenDescriptor;
    address public override localUniV3PM;
    address public override localUniV3Router;

    constructor() {
        initiate();
    }

    function initiate() internal {
        localUniV3Factory = address(new UniswapV3Factory());
        weth9 = _deployWETH9();
        localUniV3TokenDescriptor = address(0);
        localUniV3PM = address(new NonfungiblePositionManager(localUniV3Factory, weth9, localUniV3TokenDescriptor));
        localUniV3Router = address(new SwapRouter(localUniV3Factory, weth9));

        vm.label(weth9, "LocalWETH9");
        vm.label(localUniV3Factory, "LocalUniswapV3Factory");
        vm.label(localUniV3PM, "LocalUniV3NonfungiblePositionManager");
        vm.label(localUniV3Router, "LocalUniV3SwapRouter");
    }

    function _deployWETH9() internal returns (address w) {
        bytes memory bytecode = abi.encodePacked(vm.getCode("WETH9.sol:WETH9"));
        assembly {
            w := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }
}
