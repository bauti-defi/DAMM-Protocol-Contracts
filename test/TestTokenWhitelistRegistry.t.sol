// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";

import {SymTest} from "@halmos/SymTest.sol";
import {TokenWhitelistRegistry} from "@src/base/TokenWhitelistRegistry.sol";

contract TestTokenWhitelistRegistry is SymTest, Test {
    TokenWhitelistRegistry public registry;

    function setUp() public {
        registry = new TokenWhitelistRegistry();
    }

    function check_whitelist_token(address token, address otherToken, address router) external {
        vm.assume(token != address(0));

        vm.assume(token != otherToken);
        vm.assume(router != token);
        vm.assume(router != otherToken);

        registry.whitelistToken(router, token);
        assertFalse(registry.isTokenWhitelisted(address(this), router, otherToken));
        assertFalse(registry.isTokenWhitelisted(address(this), otherToken, router));
        assertFalse(registry.isTokenWhitelisted(address(this), token, router));
        assertTrue(registry.isTokenWhitelisted(address(this), router, token));
    }

    function check_blacklist_token(address token, address otherToken, address router) external {
        vm.assume(token != address(0));

        vm.assume(token != otherToken);
        vm.assume(router != token);
        vm.assume(router != otherToken);

        registry.whitelistToken(router, token);
        registry.blacklistToken(router, token);
        assertFalse(registry.isTokenWhitelisted(address(this), router, token));
        assertFalse(registry.isTokenWhitelisted(address(this), router, otherToken));
        assertFalse(registry.isTokenWhitelisted(address(this), otherToken, router));
        assertFalse(registry.isTokenWhitelisted(address(this), token, router));
    }

    function check_top_bound(address otherToken) public {
        for (uint160 i = 0; i < 300; i++) {
            vm.assume(address(i) != otherToken);
            registry.whitelistToken(address(this), address(i));
        }

        for (uint160 i = 0; i < 300; i++) {
            assertTrue(registry.isTokenWhitelisted(address(this), address(this), address(i)));
        }
        assertFalse(registry.isTokenWhitelisted(address(this), address(this), otherToken));
    }

    function check_collisions(address a, address b) public {
        vm.assume(a != b);
        assertFalse(uint256(uint160(a)) == uint256(uint160(b)));
    }
}
