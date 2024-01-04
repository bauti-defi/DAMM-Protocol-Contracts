// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {Test, console2} from "@forge-std/Test.sol";
import {BytesLib} from "@src/lib/BytesLib.sol";

contract TestUnpackingAddresses is Test {
    using BytesLib for bytes;

    function test1(address a) public {
        vm.assume(a != address(0));

        bytes memory packed = abi.encodePacked(a);

        address[] memory array = packed.unpackAddresses();

        assertEq(array[0], a);
        assertEq(array.length, 1);
    }

    function test2(address a, address b) public {
        vm.assume(a != address(0) && b != address(0));
        vm.assume(a != b);

        bytes memory packed = abi.encodePacked(a, b);

        address[] memory array = packed.unpackAddresses();

        assertEq(array[0], a);
        assertEq(array[1], b);
        assertEq(array.length, 2);
    }

    function test3(address a, address b, address c) public {
        vm.assume(a != address(0) && b != address(0) && c != address(0));
        vm.assume(a != b && a != c && b != c);

        bytes memory packed = abi.encodePacked(a, b, c);

        address[] memory array = packed.unpackAddresses();

        assertEq(array[0], a);
        assertEq(array[1], b);
        assertEq(array[2], c);
        assertEq(array.length, 3);
    }

    function testN(bytes memory packed) public {
        uint256 elementSize = 20;

        vm.assume(packed.length > 0);
        vm.assume(packed.length % elementSize == 0);

        address[] memory array = packed.unpackAddresses();

        assertEq(array.length, packed.length / elementSize);

        for (uint256 i = 0; i < array.length; i++) {
            for (uint256 j = i + 1; j < array.length; j++) {
                assertEq(bytes20(array[i])[j], packed[i * elementSize + j]);
            }
        }
    }
}
