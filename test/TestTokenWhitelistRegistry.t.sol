// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {Test} from "@forge-std/Test.sol";

import {TokenWhitelistRegistry} from "@src/base/TokenWhitelistRegistry.sol";
import {ProtocolState} from "@src/base/ProtocolState.sol";
import "@src/base/ProtocolAccessController.sol";
import "@src/base/ProtocolAddressRegistry.sol";

contract TestTokenWhitelistRegistry is Test {
    TokenWhitelistRegistry public registry;
    IProtocolAddressRegistry public addressRegistry;
    ProtocolState public protocolState;

    function setUp() public {
        ProtocolAccessController accessController = new ProtocolAccessController(address(this));
        addressRegistry =
            IProtocolAddressRegistry(new ProtocolAddressRegistry(address(accessController)));

        protocolState = new ProtocolState(addressRegistry);
        registry = new TokenWhitelistRegistry(addressRegistry);

        addressRegistry.setProtocolState(address(protocolState));
        addressRegistry.setTokenWhitelistRegistry(address(registry));
    }

    modifier validAddress(address addr) {
        vm.assume(addr != address(0));
        vm.assume(addr != address(this));
        vm.assume(!addressRegistry.isRegistered(addr));
        _;
    }

    function test_whitelist_token(address token, address otherToken, address router)
        external
        validAddress(token)
        validAddress(otherToken)
        validAddress(router)
    {
        vm.assume(router != token);
        vm.assume(router != otherToken);
        vm.assume(token != otherToken);

        registry.whitelistToken(router, token);
        assertFalse(registry.isTokenWhitelisted(address(this), router, otherToken));
        assertFalse(registry.isTokenWhitelisted(address(this), otherToken, router));
        assertFalse(registry.isTokenWhitelisted(address(this), token, router));
        assertTrue(registry.isTokenWhitelisted(address(this), router, token));
    }

    function test_blacklist_token(address token, address otherToken, address router)
        external
        validAddress(token)
        validAddress(otherToken)
        validAddress(router)
    {
        vm.assume(router != token);
        vm.assume(router != otherToken);
        vm.assume(token != otherToken);

        registry.whitelistToken(router, token);
        registry.blacklistToken(router, token);
        assertFalse(registry.isTokenWhitelisted(address(this), router, token));
        assertFalse(registry.isTokenWhitelisted(address(this), router, otherToken));
        assertFalse(registry.isTokenWhitelisted(address(this), otherToken, router));
        assertFalse(registry.isTokenWhitelisted(address(this), token, router));
    }

    function test_cannot_whitelist_self_as_token() public {
        vm.expectRevert("TokenWhitelistRegistry: sender address");
        registry.whitelistToken(address(999), address(this));
    }

    function test_cannot_whitelist_self_as_router() public {
        vm.expectRevert("TokenWhitelistRegistry: sender address");
        registry.whitelistToken(address(this), address(999));
    }

    function test_cannot_whitelist_zero_as_token() public {
        vm.expectRevert("TokenWhitelistRegistry: zero address");
        registry.whitelistToken(address(999), address(0));
    }

    function test_cannot_whitelist_zero_as_router() public {
        vm.expectRevert("TokenWhitelistRegistry: zero address");
        registry.whitelistToken(address(0), address(999));
    }

    function test_cannot_whitelist_registry_as_token() public {
        vm.expectRevert("TokenWhitelistRegistry: self address");
        registry.whitelistToken(address(registry), address(999));
    }

    function test_cannot_whitelist_registry_as_router() public {
        vm.expectRevert("TokenWhitelistRegistry: self address");
        registry.whitelistToken(address(999), address(registry));
    }

    function test_cannot_whitelist_reserved_address_as_router() public {
        vm.expectRevert("TokenWhitelistRegistry: reserved address");
        registry.whitelistToken(address(addressRegistry), address(999));
    }

    function test_cannot_whitelist_reserved_address_as_token() public {
        vm.expectRevert("TokenWhitelistRegistry: reserved address");
        registry.whitelistToken(address(999), address(addressRegistry));
    }

    function test_cannot_whitelist_when_paused() public {
        protocolState.pause();
        vm.expectRevert("ProtocolState: stopped");
        registry.whitelistToken(address(this), address(this));
    }

    function test_can_blacklist_when_paused(address token, address router)
        public
        validAddress(token)
        validAddress(router)
    {
        vm.assume(router != token);

        registry.whitelistToken(router, token);
        protocolState.pause();

        registry.blacklistToken(router, token);
        assertFalse(registry.isTokenWhitelisted(address(this), router, token));
    }
}
