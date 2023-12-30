// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";

import {SymTest} from "@halmos/SymTest.sol";
import {RouterWhitelistRegistry} from "@src/base/RouterWhitelistRegistry.sol";

contract TestRouterWhitelistRegistry is SymTest, Test {
    RouterWhitelistRegistry public registry;

    function setUp() public {
        registry = new RouterWhitelistRegistry();
    }

    function check_whitelist_router(address router, address otherRouter) external {
        vm.assume(router != address(0));

        vm.assume(router != otherRouter);

        registry.whitelistRouter(router);
        assertFalse(registry.isRouterWhitelisted(address(this), otherRouter));
        assertTrue(registry.isRouterWhitelisted(address(this), router));
    }

    function check_blacklist_router(address router, address otherRouter) external {
        vm.assume(router != address(0));

        vm.assume(router != otherRouter);

        registry.whitelistRouter(router);
        registry.blacklistRouter(router);
        assertFalse(registry.isRouterWhitelisted(address(this), router));
        assertFalse(registry.isRouterWhitelisted(address(this), otherRouter));
    }

    function check_top_bound(address otherRouter) public {
        vm.assume(otherRouter != address(0));
        vm.assume(otherRouter != address(this));
        vm.assume(otherRouter != address(registry));

        for (uint160 i = 0; i < 254; i++) {
            vm.assume(address(i) != otherRouter);
            registry.whitelistRouter(address(i));
        }

        assertFalse(registry.isRouterWhitelisted(address(this), otherRouter));
    }

    function check_collisions(address a, address b) public {
        vm.assume(a != b);
        assertFalse(uint256(uint160(a)) == uint256(uint160(b)));
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
