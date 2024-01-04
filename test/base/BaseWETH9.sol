// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {Test} from "@forge-std/Test.sol";
import {IWETH9} from "@src/interfaces/external/IWETH9.sol";

abstract contract BaseWETH9 is Test {
    IWETH9 public WETH9;

    function setUp() public virtual {
        WETH9 = IWETH9(_deployWETH9());

        vm.label(address(WETH9), "WETH9");
    }

    function _deployWETH9() internal returns (address w) {
        bytes memory bytecode = abi.encodePacked(vm.getCode("WETH9.sol:WETH9"));
        assembly {
            w := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }
}
