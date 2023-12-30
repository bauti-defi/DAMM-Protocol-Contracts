// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {ITokenWhitelistRegistry} from "@src/interfaces/ITokenWhitelistRegistry.sol";
import {BitMaps} from "@openzeppelin-contracts/utils/structs/BitMaps.sol";
import {AddressConverter} from "@src/lib/AddressConverter.sol";

/// @notice This registry does not yet support native ethereum tokens
/// @notice This registristry supports up to 256 tokens per router per user
contract TokenWhitelistRegistry is ITokenWhitelistRegistry {
    using BitMaps for BitMaps.BitMap;
    using AddressConverter for address;

    /// @notice keccak256(abi.encodePacked(user, router)) => whitelisted
    mapping(bytes32 pointer => BitMaps.BitMap token) internal tokenWhitelist;

    function _tokenPointer(address user, address router) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, router));
    }

    function isTokenWhitelisted(address user, address router, address token) external view returns (bool) {
        return tokenWhitelist[_tokenPointer(user, router)].get(token.toUint256());
    }

    function _whitelistToken(address router, address token) internal {
        tokenWhitelist[_tokenPointer(msg.sender, router)].setTo(token.toUint256(), true);
    }

    function _blacklistToken(address router, address token) internal {
        tokenWhitelist[_tokenPointer(msg.sender, router)].setTo(token.toUint256(), false);
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

        for (uint256 i = 0; i < length;) {
            _whitelistToken(routers[i], tokens[i]);

            unchecked {
                ++i;
            }
        }

        emit TokensWhitelisted(msg.sender, routers, tokens);
    }

    function blacklistTokens(address[] memory routers, address[] memory tokens) external {
        uint256 length = tokens.length;

        require(length == routers.length, "TokenWhitelistRegistry: routers and tokens length mismatch");

        for (uint256 i = 0; i < length;) {
            _blacklistToken(routers[i], tokens[i]);

            unchecked {
                ++i;
            }
        }

        emit TokensBlacklisted(msg.sender, routers, tokens);
    }
}
