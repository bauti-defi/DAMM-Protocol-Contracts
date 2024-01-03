// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IRouterWhitelistRegistry {
    event RouterWhitelisted(address indexed user, address router);
    event RoutersWhitelisted(address indexed user, address[] routers);
    event RouterBlacklisted(address indexed user, address router);
    event RoutersBlacklisted(address indexed user, address[] routers);

    function isRouterWhitelisted(address user, address router) external view returns (bool);

    function whitelistRouter(address router) external;

    function blacklistRouter(address router) external;

    function whitelistRouters(address[] memory routers) external;

    function blacklistRouters(address[] memory routers) external;
}
