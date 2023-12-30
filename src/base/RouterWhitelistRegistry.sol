// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {BitMaps} from "@openzeppelin-contracts/utils/structs/BitMaps.sol";
import {IRouterWhitelistRegistry} from "@src/interfaces/IRouterWhitelistRegistry.sol";
import {AddressConverter} from "@src/lib/AddressConverter.sol";

contract RouterWhitelistRegistry is IRouterWhitelistRegistry {
    using BitMaps for BitMaps.BitMap;
    using AddressConverter for address;

    mapping(address vault => BitMaps.BitMap router) internal routerWhitelist;

    function isRouterWhitelisted(address vault, address router) external view returns (bool) {
        return routerWhitelist[vault].get(router.toUint256());
    }

    function _whitelistRouter(address router) internal {
        routerWhitelist[msg.sender].setTo(router.toUint256(), true);
    }

    function _blacklistRouter(address router) internal {
        routerWhitelist[msg.sender].setTo(router.toUint256(), false);
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
