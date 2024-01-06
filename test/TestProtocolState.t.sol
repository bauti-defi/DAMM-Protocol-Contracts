// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {Test} from "@forge-std/Test.sol";
import {ProtocolState} from "@src/base/ProtocolState.sol";
import {ProtocolAccessController} from "@src/base/ProtocolAccessController.sol";
import {ProtocolAddressRegistry} from "@src/base/ProtocolAddressRegistry.sol";
import {IProtocolAddressRegistry} from "@src/interfaces/IProtocolAddressRegistry.sol";
import {IProtocolState} from "@src/interfaces/IProtocolState.sol";

contract TestProtocolState is Test {
    uint256 internal constant PAUSER_ROLE = 1 << 0;

    ProtocolAccessController public protocolAccessController;
    ProtocolAddressRegistry public protocolAddressRegistry;
    ProtocolState public protocolState;

    function setUp() public {
        protocolAccessController = new ProtocolAccessController(address(this));
        protocolAddressRegistry = new ProtocolAddressRegistry(address(protocolAccessController));
        protocolState = new ProtocolState(IProtocolAddressRegistry(protocolAddressRegistry));
    }

    function test_pause() public {
        protocolState.pause();

        assertTrue(protocolState.paused());

        protocolState.unpause();

        assertFalse(protocolState.paused());
    }

    function test_only_owner_or_pauser_can_pause(address pauser, address notPauser, uint256 randomRole) public {
        vm.assume(pauser != address(this));
        vm.assume(pauser != notPauser);
        vm.assume(randomRole & PAUSER_ROLE == 0);

        protocolAccessController.grantRoles(pauser, PAUSER_ROLE);

        vm.expectRevert();
        vm.prank(notPauser);
        protocolState.pause();

        protocolAccessController.grantRoles(notPauser, randomRole);
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
}
