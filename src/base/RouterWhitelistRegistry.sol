// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {IRouterWhitelistRegistry} from "@src/interfaces/IRouterWhitelistRegistry.sol";
import {IProtocolState} from "@src/interfaces/IProtocolState.sol";
import {IProtocolAddressRegistry} from "@src/interfaces/IProtocolAddressRegistry.sol";
import {SafeGet} from "@src/lib/SafeGet.sol";

contract RouterWhitelistRegistry is IRouterWhitelistRegistry {
    using SafeGet for address;

    IProtocolAddressRegistry private immutable ADDRESS_REGISTRY;

    mapping(bytes32 pointer => bool whitelisted) internal routerWhitelist;

    constructor(IProtocolAddressRegistry addressRegistry) {
        ADDRESS_REGISTRY = IProtocolAddressRegistry(addressRegistry);
    }

    function _pointer(address vault, address router) internal pure returns (bytes32) {
        return keccak256(abi.encode(vault, router));
    }

    function isRouterWhitelisted(address vault, address router) external view returns (bool) {
        return routerWhitelist[_pointer(vault, router)];
    }

    function _whitelistRouter(address to, address router) internal {
        IProtocolState(ADDRESS_REGISTRY.getProtocolState().orRevert()).requireNotStopped();

        require(router != address(0), "RouterWhitelistRegistry: zero address");
        require(router != address(this), "RouterWhitelistRegistry: self address");
        require(router != to, "RouterWhitelistRegistry: sender address");

        routerWhitelist[_pointer(to, router)] = true;
    }

    function whitelistRouter(address router) external {
        _whitelistRouter(msg.sender, router);

        emit RouterWhitelisted(msg.sender, router);
    }

    function _whitelistRouters(address to, address[] memory routers) internal {
        uint256 length = routers.length;

        for (uint256 i = 0; i < length;) {
            _whitelistRouter(to, routers[i]);

            unchecked {
                ++i;
            }
        }

        emit RoutersWhitelisted(to, routers);
    }

    function whitelistRouters(address[] memory routers) external {
        _whitelistRouters(msg.sender, routers);
    }

    function _blacklistRouter(address to, address router) internal {
        require(router != address(0), "RouterWhitelistRegistry: zero address");

        routerWhitelist[_pointer(to, router)] = false;
    }

    function blacklistRouter(address router) external {
        _blacklistRouter(msg.sender, router);

        emit RouterBlacklisted(msg.sender, router);
    }

    function _blacklistRouters(address to, address[] memory routers) internal {
        uint256 length = routers.length;

        for (uint256 i = 0; i < length;) {
            _blacklistRouter(to, routers[i]);

            unchecked {
                ++i;
            }
        }

        emit RoutersBlacklisted(to, routers);
    }

    function blacklistRouters(address[] memory routers) external {
        _blacklistRouters(msg.sender, routers);
    }
}
