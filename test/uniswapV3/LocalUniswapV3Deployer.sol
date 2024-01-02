// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6;
pragma abicoder v2;

import {Vm} from "@forge-std/Vm.sol";
import {UniswapV3Factory} from "@uniswap-v3-core/UniswapV3Factory.sol";
import {IUniswapV3Factory} from "@uniswap-v3-core/interfaces/IUniswapV3Factory.sol";
import {NonfungiblePositionManager} from "@uniswap-v3-periphery/NonfungiblePositionManager.sol";
import {INonfungiblePositionManager} from "@uniswap-v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {SwapRouter} from "@uniswap-v3-periphery/SwapRouter.sol";
import {ISwapRouter} from "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import {IBaseUniswapV3} from "@test/uniswapV3/IBaseUniswapV3.sol";
import {TickMath} from "@test/utils/TickMath.sol";

contract Deployer is IBaseUniswapV3 {
    // Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm internal constant vm = Vm(VM_ADDRESS);

    address public override localUniV3Factory;
    address public override weth9;
    address public override localUniV3TokenDescriptor;
    address public override localUniV3PM;
    address public override localUniV3Router;

    modifier initialized() {
        require(localUniV3Factory != address(0), "Deployer: not initialized");
        _;
    }

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

    function deployPool(address token0, address token1, uint24 poolFee)
        external
        override
        initialized
        returns (address pool)
    {
        (bool success, bytes memory result) = localUniV3Factory.call(
            abi.encodeWithSelector(bytes4(keccak256("createPool(address,address,uint24)")), token0, token1, poolFee)
        );

        require(success, "createPool failed");
        pool = abi.decode(result, (address));

        vm.label(pool, "Pool");
    }

    function initializePool(address pool, int24 startTick) external override initialized {
        (bool success,) = pool.call(
            abi.encodeWithSelector(bytes4(keccak256("initialize(uint160)")), TickMath.getSqrtRatioAtTick(startTick))
        );

        require(success, "pool initialize failed");
    }
}
