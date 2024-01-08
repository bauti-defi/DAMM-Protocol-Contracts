// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {Test, console2} from "@forge-std/Test.sol";

import {RouterWhitelistRegistry} from "@src/base/RouterWhitelistRegistry.sol";
import {ProtocolState} from "@src/base/ProtocolState.sol";
import "@src/base/ProtocolAccessController.sol";
import "@src/base/ProtocolAddressRegistry.sol";

contract TestRouterWhitelistRegistry is Test {
    RouterWhitelistRegistry public registry;
    ProtocolState public protocolState;

    function setUp() public {
        ProtocolAccessController accessController = new ProtocolAccessController(address(this));
        IProtocolAddressRegistry addressRegistry =
            IProtocolAddressRegistry(new ProtocolAddressRegistry(address(accessController)));

        protocolState = new ProtocolState(addressRegistry);
        registry = new RouterWhitelistRegistry(addressRegistry);

        addressRegistry.setProtocolState(address(protocolState));
        addressRegistry.setRouterWhitelistRegistry(address(registry));
    }

    function test_whitelist_router(address router, address otherRouter) external {
        vm.assume(router != address(0));
        vm.assume(router != address(this));
        vm.assume(router != otherRouter);
        vm.assume(router != address(registry));

        registry.whitelistRouter(router);
        assertFalse(registry.isRouterWhitelisted(address(this), otherRouter));
        assertTrue(registry.isRouterWhitelisted(address(this), router));
    }

    function test_blacklist_router(address router, address otherRouter) external {
        vm.assume(router != address(0));
        vm.assume(router != address(this));
        vm.assume(router != address(registry));
        vm.assume(router != otherRouter);

        registry.whitelistRouter(router);
        registry.blacklistRouter(router);
        assertFalse(registry.isRouterWhitelisted(address(this), router));
        assertFalse(registry.isRouterWhitelisted(address(this), otherRouter));
    }

    function test_cannot_whitelist_self() public {
        vm.expectRevert("RouterWhitelistRegistry: sender address");
        registry.whitelistRouter(address(this));
    }

    function test_cannot_whitelist_zero() public {
        vm.expectRevert("RouterWhitelistRegistry: zero address");
        registry.whitelistRouter(address(0));
    }

    function test_cannot_whitelist_registry() public {
        vm.expectRevert("RouterWhitelistRegistry: self address");
        registry.whitelistRouter(address(registry));
    }

    function test_cannot_whitelist_when_paused() public {
        protocolState.pause();
        vm.expectRevert("ProtocolState: stopped");
        registry.whitelistRouter(address(this));
    }

    function test_can_blacklist_when_paused(address router) public {
        vm.assume(router != address(0));
        vm.assume(router != address(this));
        vm.assume(router != address(registry));

        registry.whitelistRouter(router);
        protocolState.pause();

        registry.blacklistRouter(router);
        assertFalse(registry.isRouterWhitelisted(address(this), router));
    }
}
