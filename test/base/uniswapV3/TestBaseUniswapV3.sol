// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import {Test} from "@forge-std/Test.sol";
import {IBaseUniswapV3} from "@test/base/uniswapV3/IBaseUniswapV3.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";

abstract contract TestBaseUniswapV3 is TestBaseProtocol {
    IBaseUniswapV3 public uniswapV3;

    function setUp() public virtual override {
        super.setUp();

        uniswapV3 = _deployUniswapV3();
    }

    function _deployUniswapV3() internal returns (IBaseUniswapV3) {
        bytes memory bytecode = abi.encodePacked(vm.getCode("LocalUniswapV3Deployer.sol:Deployer"));
        address deployer;
        assembly {
            deployer := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        return IBaseUniswapV3(deployer);
    }
}
