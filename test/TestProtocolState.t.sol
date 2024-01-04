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
    uint256 internal constant PAUSER_ROLE = 1 << 0;

    Target public target;
    ProtocolState public protocolState;

    function setUp() public {
        protocolState = new ProtocolState(address(this));
        target = new Target(address(protocolState));
    }

    function test_pause() public {
        protocolState.pause();

        vm.expectRevert();
        target.add(1, 2);
        assertEq(target.state(), 0);

        target.sub(10, 5);
        assertEq(target.state(), 5);

        protocolState.unpause();

        target.add(1, 2);
        assertEq(target.state(), 3);

        vm.expectRevert();
        target.sub(10, 5);
        assertEq(target.state(), 3);
    }

    function test_only_owner_or_pauser_can_pause(address pauser, address notPauser, uint256 randomRole) public {
        vm.assume(pauser != address(this));
        vm.assume(pauser != notPauser);
        vm.assume(randomRole & PAUSER_ROLE == 0);

        protocolState.grantRoles(pauser, PAUSER_ROLE);

        vm.expectRevert();
        vm.prank(notPauser);
        protocolState.pause();

        protocolState.grantRoles(notPauser, randomRole);
        vm.expectRevert();
        vm.prank(notPauser);
        protocolState.pause();

        vm.prank(pauser);
        protocolState.pause();
        assertTrue(protocolState.paused());

        protocolState.unpause();
        assertFalse(protocolState.paused());
        protocolState.pause();
        assertTrue(protocolState.paused());
    }

    function test_only_admin_can_unpause(address pauser) public {
        vm.assume(pauser != address(this));
        vm.expectRevert();
        vm.prank(pauser);
        protocolState.unpause();
    }

    function test_sweep() public {
        vm.deal(address(protocolState), 1 ether);

        uint256 balance = address(this).balance;

        protocolState.sweep();

        assertEq(address(this).balance, balance + 1 ether);
        assertEq(address(protocolState).balance, 0);
    }

    receive() external payable {}
}
