// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {ITokenWhitelistRegistry} from "@src/interfaces/ITokenWhitelistRegistry.sol";
import {IProtocolState} from "@src/interfaces/IProtocolState.sol";
import {IProtocolAddressRegistry} from "@src/interfaces/IProtocolAddressRegistry.sol";
import {SafeGet} from "@src/lib/SafeGet.sol";

/// @notice This registry does not yet support native ethereum tokens
contract TokenWhitelistRegistry is ITokenWhitelistRegistry {
    using SafeGet for address;

    IProtocolAddressRegistry private immutable ADDRESS_REGISTRY;

    /// @notice keccak256(abi.encodePacked(user, router, token)) => whitelisted
    mapping(bytes32 pointer => bool whitelisted) internal tokenWhitelist;

    constructor(IProtocolAddressRegistry addressRegistry) {
        ADDRESS_REGISTRY = IProtocolAddressRegistry(addressRegistry);
    }

    function _tokenPointer(address user, address router, address token)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(user, router, token));
    }

    function isTokenWhitelisted(address user, address router, address token)
        external
        view
        returns (bool)
    {
        return tokenWhitelist[_tokenPointer(user, router, token)];
    }

    function _whitelistToken(address router, address token) internal {
        IProtocolState(ADDRESS_REGISTRY.getProtocolState().orRevert()).requireNotStopped();

        require(token != address(0), "TokenWhitelistRegistry: zero address");
        require(token != address(this), "TokenWhitelistRegistry: self address");
        require(token != msg.sender, "TokenWhitelistRegistry: sender address");

        tokenWhitelist[_tokenPointer(msg.sender, router, token)] = true;
    }

    function whitelistToken(address router, address token) external {
        _whitelistToken(router, token);

        emit TokenWhitelisted(msg.sender, router, token);
    }

    function whitelistTokens(address[] memory routers, address[] memory tokens) external {
        uint256 length = tokens.length;

        require(
            length == routers.length, "TokenWhitelistRegistry: routers and tokens length mismatch"
        );

        for (uint256 i = 0; i < length;) {
            _whitelistToken(routers[i], tokens[i]);

            unchecked {
                ++i;
            }
        }

        emit TokensWhitelisted(msg.sender, routers, tokens);
    }

    function _blacklistToken(address router, address token) internal {
        require(token != address(0), "TokenWhitelistRegistry: zero address");

        tokenWhitelist[_tokenPointer(msg.sender, router, token)] = false;
    }

    function blacklistToken(address router, address token) external {
        _blacklistToken(router, token);

        emit TokenBlacklisted(msg.sender, router, token);
    }

    function blacklistTokens(address[] memory routers, address[] memory tokens) external {
        uint256 length = tokens.length;

        require(
            length == routers.length, "TokenWhitelistRegistry: routers and tokens length mismatch"
        );

        for (uint256 i = 0; i < length;) {
            _blacklistToken(routers[i], tokens[i]);

            unchecked {
                ++i;
            }
        }

        emit TokensBlacklisted(msg.sender, routers, tokens);
    }
}
