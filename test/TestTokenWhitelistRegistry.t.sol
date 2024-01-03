// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";

import {SymTest} from "@halmos/SymTest.sol";
import {TokenWhitelistRegistry} from "@src/base/TokenWhitelistRegistry.sol";
import {ProtocolState} from "@src/base/ProtocolState.sol";

contract TestTokenWhitelistRegistry is SymTest, Test {
    TokenWhitelistRegistry public registry;
    ProtocolState public protocolState;

    function setUp() public {
        protocolState = new ProtocolState(address(this));
        registry = new TokenWhitelistRegistry(address(protocolState));
    }

    function check_whitelist_token(address token, address otherToken, address router) external {
        vm.assume(token != address(0));
        vm.assume(token != address(this));
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
        vm.assume(token != address(this));
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

    function test_cannot_whitelist_self() public {
        vm.expectRevert("TokenWhitelistRegistry: sender address");
        registry.whitelistToken(address(this), address(this));
    }

    function test_cannot_whitelist_zero() public {
        vm.expectRevert("TokenWhitelistRegistry: zero address");
        registry.whitelistToken(address(this), address(0));
    }

    function test_cannot_whitelist_registry() public {
        vm.expectRevert("TokenWhitelistRegistry: self address");
        registry.whitelistToken(address(this), address(registry));
    }
}
