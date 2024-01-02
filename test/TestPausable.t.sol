// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";

import {Pausable} from "@src/lib/Pausable.sol";

contract Target is Pausable {
    uint256 public state;

    constructor(address _admin) Pausable(_admin) {}

    function add(uint256 a, uint256 b) external notPaused {
        state = a + b;
    }

    function sub(uint256 a, uint256 b) external isPaused {
        state = a - b;
    }
}

contract TestPausable is Test {
    Target public target;

    function setUp() public {
        target = new Target(address(this));
    }

    function test() public {
        target.pause();

        vm.expectRevert();
        target.add(1, 2);
        assertEq(target.state(), 0);

        target.sub(10, 5);
        assertEq(target.state(), 5);

        target.unpause();

        target.add(1, 2);
        assertEq(target.state(), 3);

        vm.expectRevert();
        target.sub(10, 5);
        assertEq(target.state(), 3);
    }

    function test_only_admin_can_pause(address pauser) public {
        vm.assume(pauser != address(this));
        vm.expectRevert("Pausable: Only admin can pause");
        vm.prank(pauser);
        target.pause();
    }

    function test_only_admin_can_unpause(address pauser) public {
        vm.assume(pauser != address(this));
        vm.expectRevert("Pausable: Only admin can unpause");
        vm.prank(pauser);
        target.unpause();
    }
}
