// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {Test} from "@forge-std/Test.sol";
import {BasePausable} from "@src/base/BasePausable.sol";
import {IProtocolStateActions} from "@src/interfaces/IProtocolStateActions.sol";
import {ProtocolState} from "@src/base/ProtocolState.sol";

contract Target is BasePausable {
    uint256 public state;

    constructor(address _protocolState) BasePausable(_protocolState) {}

    function add(uint256 a, uint256 b) external notPaused {
        state = a + b;
    }

    function sub(uint256 a, uint256 b) external isPaused {
        state = a - b;
    }
}

contract TestProtocolState is Test {
    Target public target;
    address public protocolState;

    function setUp() public {
        protocolState = address(new ProtocolState(address(this)));
        target = new Target(protocolState);
    }

    function test_pause() public {
        IProtocolStateActions(protocolState).pause();

        vm.expectRevert();
        target.add(1, 2);
        assertEq(target.state(), 0);

        target.sub(10, 5);
        assertEq(target.state(), 5);

        IProtocolStateActions(protocolState).unpause();

        target.add(1, 2);
        assertEq(target.state(), 3);

        vm.expectRevert();
        target.sub(10, 5);
        assertEq(target.state(), 3);
    }

    function test_only_admin_can_pause(address pauser) public {
        vm.assume(pauser != address(this));
        vm.expectRevert();
        vm.prank(pauser);
        IProtocolStateActions(protocolState).pause();
    }

    function test_only_admin_can_unpause(address pauser) public {
        vm.assume(pauser != address(this));
        vm.expectRevert();
        vm.prank(pauser);
        IProtocolStateActions(protocolState).unpause();
    }

    function test_sweep() public {
        vm.deal(protocolState, 1 ether);

        uint256 balance = address(this).balance;

        IProtocolStateActions(protocolState).sweep();

        assertEq(address(this).balance, balance + 1 ether);
        assertEq(protocolState.balance, 0);
    }

    receive() external payable {}
}
