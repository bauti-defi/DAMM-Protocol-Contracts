// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";

import {ReentrancyGuard} from "@src/lib/ReentrancyGuard.sol";

interface ITester {
    function test_guard() external;
}

contract Caller {
    function call_tester() external {
        ITester(msg.sender).test_guard();
    }
}

contract TestReentrancyGuard is ITester, ReentrancyGuard, Test {
    Caller caller;

    function setUp() public {
        caller = new Caller();
    }

    function test_guard() external nonReentrant {
        vm.expectRevert();
        caller.call_tester();
    }
}
