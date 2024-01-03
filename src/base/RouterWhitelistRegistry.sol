// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IRouterWhitelistRegistry} from "@src/interfaces/IRouterWhitelistRegistry.sol";
import {ProtocolStateAccesor} from "@src/lib/ProtocolStateAccesor.sol";

contract RouterWhitelistRegistry is ProtocolStateAccesor, IRouterWhitelistRegistry {
    mapping(bytes32 pointer => bool whitelisted) internal routerWhitelist;

    constructor(address _protocolState) ProtocolStateAccesor(_protocolState) {}

    function _pointer(address vault, address router) internal pure returns (bytes32) {
        return keccak256(abi.encode(vault, router));
    }

    function isRouterWhitelisted(address vault, address router) external view returns (bool) {
        return routerWhitelist[_pointer(vault, router)];
    }

    function _whitelistRouter(address router) internal notPaused {
        require(router != address(0), "RouterWhitelistRegistry: zero address");
        require(router != address(this), "RouterWhitelistRegistry: self address");
        require(router != msg.sender, "RouterWhitelistRegistry: sender address");

        routerWhitelist[_pointer(msg.sender, router)] = true;
    }

    function _blacklistRouter(address router) internal notPaused {
        require(router != address(0), "RouterWhitelistRegistry: zero address");

        routerWhitelist[_pointer(msg.sender, router)] = false;
    }

    function whitelistRouter(address router) external {
        _whitelistRouter(router);

        emit RouterWhitelisted(msg.sender, router);
    }

    function blacklistRouter(address router) external {
        _blacklistRouter(router);

        emit RouterBlacklisted(msg.sender, router);
    }

    function whitelistRouters(address[] memory routers) external {
        uint256 length = routers.length;

        for (uint256 i = 0; i < length;) {
            _whitelistRouter(routers[i]);

            unchecked {
                ++i;
            }
        }

        emit RoutersWhitelisted(msg.sender, routers);
    }

    function blacklistRouters(address[] memory routers) external {
        uint256 length = routers.length;

        for (uint256 i = 0; i < length;) {
            _blacklistRouter(routers[i]);

            unchecked {
                ++i;
            }
        }

        emit RoutersBlacklisted(msg.sender, routers);
    }
}
