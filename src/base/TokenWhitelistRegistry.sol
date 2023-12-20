// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {ITokenWhitelistRegistry} from "@src/interfaces/ITokenWhitelistRegistry.sol";

/// @notice This registry does not yet support native ethereum tokens
contract TokenWhitelistRegistry is ITokenWhitelistRegistry {
    /// @notice keccak256(abi.encode(user, router, token)) => whitelisted
    mapping(bytes32 tokenPointer => bool whitelisted) internal tokenWhitelist;

    function _tokenPointer(address user, address router, address token) internal pure returns (bytes32) {
        return keccak256(abi.encode(user, router, token));
    }

    function isTokenWhitelisted(address user, address router, address token) external view returns (bool) {
        return tokenWhitelist[_tokenPointer(user, router, token)];
    }

    function _whitelistToken(address router, address token) internal {
        tokenWhitelist[_tokenPointer(msg.sender, router, token)] = true;
    }

    function _blacklistToken(address router, address token) internal {
        tokenWhitelist[_tokenPointer(msg.sender, router, token)] = false;
    }

    function whitelistToken(address router, address token) external {
        _whitelistToken(router, token);

        emit TokenWhitelisted(msg.sender, router, token);
    }

    function blacklistToken(address router, address token) external {
        _blacklistToken(router, token);

        emit TokenBlacklisted(msg.sender, router, token);
    }

    function whitelistTokens(address[] memory routers, address[] memory tokens) external {
        uint256 length = tokens.length;

        require(length == routers.length, "TokenWhitelistRegistry: routers and tokens length mismatch");

        for (uint256 i = 0; i < length; i++) {
            _whitelistToken(routers[i], tokens[i]);
        }

        emit TokensWhitelisted(msg.sender, routers, tokens);
    }

    function blacklistTokens(address[] memory routers, address[] memory tokens) external {
        uint256 length = tokens.length;

        require(length == routers.length, "TokenWhitelistRegistry: routers and tokens length mismatch");

        for (uint256 i = 0; i < length; i++) {
            _blacklistToken(routers[i], tokens[i]);
        }

        emit TokensBlacklisted(msg.sender, routers, tokens);
    }
}
