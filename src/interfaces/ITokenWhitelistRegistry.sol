// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface ITokenWhitelistRegistry {
    event TokenWhitelisted(address indexed user, address router, address token);
    event TokensWhitelisted(address indexed user, address[] routers, address[] tokens);
    event TokenBlacklisted(address indexed user, address router, address token);
    event TokensBlacklisted(address indexed user, address[] routers, address[] tokens);

    function isTokenWhitelisted(address user, address router, address token) external view returns (bool);

    function whitelistToken(address router, address token) external;

    function blacklistToken(address router, address token) external;

    function whitelistTokens(address[] memory routers, address[] memory tokens) external;

    function blacklistTokens(address[] memory routers, address[] memory tokens) external;
}
