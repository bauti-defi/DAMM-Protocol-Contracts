// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {Test, console2} from "@forge-std/Test.sol";

import {SymTest} from "@halmos/SymTest.sol";
import {RouterWhitelistRegistry} from "@src/base/RouterWhitelistRegistry.sol";
import {ProtocolState} from "@src/base/ProtocolState.sol";

contract TestRouterWhitelistRegistry is SymTest, Test {
    RouterWhitelistRegistry public registry;
    ProtocolState public protocolState;

    function setUp() public {
        protocolState = new ProtocolState(address(this));
        registry = new RouterWhitelistRegistry(address(protocolState));
    }

    function check_whitelist_router(address router, address otherRouter) external {
        vm.assume(router != address(0));
        vm.assume(router != address(this));
        vm.assume(router != otherRouter);

        registry.whitelistRouter(router);
        assertFalse(registry.isRouterWhitelisted(address(this), otherRouter));
        assertTrue(registry.isRouterWhitelisted(address(this), router));
    }

    function check_blacklist_router(address router, address otherRouter) external {
        vm.assume(router != address(0));
        vm.assume(router != address(this));
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
}
