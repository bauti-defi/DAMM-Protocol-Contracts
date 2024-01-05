// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.0;

import {TestBase} from "@forge-std/Base.sol";

abstract contract TestBaseWETH9 is TestBase {
    address private WETH9;

    function _getWETH9() internal returns (address w) {
        if (WETH9 != address(0)) {
            uint256 size;
            address _WETH9 = WETH9;

            assembly {
                size := extcodesize(_WETH9)
            }

            if (size > 0) {
                return WETH9;
            }
        }

        bytes memory bytecode = abi.encodePacked(vm.getCode("WETH9.sol:WETH9"));
        bytes32 salt = keccak256(abi.encodePacked("WETH9.sol:WETH9"));

        /// @dev assure that the is always deployed to the same address
        vm.prank(VM_ADDRESS);
        assembly {
            w := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }

        WETH9 = w;
        vm.label(w, "WETH9");
    }
}
