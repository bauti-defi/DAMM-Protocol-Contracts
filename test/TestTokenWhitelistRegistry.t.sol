// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {Test} from "@forge-std/Test.sol";

import {TokenWhitelistRegistry} from "@src/base/TokenWhitelistRegistry.sol";
import {ProtocolState} from "@src/base/ProtocolState.sol";
import "@src/base/ProtocolAccessController.sol";
import "@src/base/ProtocolAddressRegistry.sol";

contract TestTokenWhitelistRegistry is Test {
    TokenWhitelistRegistry public registry;
    ProtocolState public protocolState;

    function setUp() public {
        ProtocolAccessController accessController = new ProtocolAccessController(address(this));
        IProtocolAddressRegistry addressRegistry =
            IProtocolAddressRegistry(new ProtocolAddressRegistry(address(accessController)));

        protocolState = new ProtocolState(addressRegistry);
        registry = new TokenWhitelistRegistry(addressRegistry);

        addressRegistry.setProtocolState(address(protocolState));
        addressRegistry.setTokenWhitelistRegistry(address(registry));
    }

    function test_whitelist_token(address token, address otherToken, address router) external {
        vm.assume(token != address(0));
        vm.assume(token != address(this));
        vm.assume(token != otherToken);
        vm.assume(token != address(registry));
        vm.assume(router != token);
        vm.assume(router != otherToken);
        vm.assume(router != address(registry));

        registry.whitelistToken(router, token);
        assertFalse(registry.isTokenWhitelisted(address(this), router, otherToken));
        assertFalse(registry.isTokenWhitelisted(address(this), otherToken, router));
        assertFalse(registry.isTokenWhitelisted(address(this), token, router));
        assertTrue(registry.isTokenWhitelisted(address(this), router, token));
    }

    function test_blacklist_token(address token, address otherToken, address router) external {
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

    function test_cannot_whitelist_when_paused() public {
        protocolState.pause();
        vm.expectRevert("ProtocolState: stopped");
        registry.whitelistToken(address(this), address(this));
    }

    function test_can_blacklist_when_paused(address token, address router) public {
        vm.assume(token != address(0));
        vm.assume(token != address(this));
        vm.assume(token != address(registry));
        vm.assume(router != token);
        vm.assume(router != address(registry));

        registry.whitelistToken(router, token);
        protocolState.pause();

        registry.blacklistToken(router, token);
        assertFalse(registry.isTokenWhitelisted(address(this), router, token));
    }
}
