// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test, console2} from "@forge-std/Test.sol";

contract TestPacking is Test {
    function test(bytes memory tokens) public {
        vm.assume(tokens.length % 20 == 0);

        // uint256[] memory tokenAddresses = new uint256[](tokens.length / 20);
    }
}
