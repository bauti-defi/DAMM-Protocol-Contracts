// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {ITokenWhitelistRegistry} from "@src/interfaces/ITokenWhitelistRegistry.sol";
import {LibMulticaller} from "@vec-multicaller/LibMulticaller.sol";
import {BytesLib} from "@src/lib/BytesLib.sol";
import {IProtocolState} from "@src/interfaces/IProtocolState.sol";
import {IProtocolAddressRegistry} from "@src/interfaces/IProtocolAddressRegistry.sol";

abstract contract BaseRouter {
    using BytesLib for bytes;

    error InvalidRecipient();
    error TokenNotWhitelisted();

    modifier setCaller() {
        if (caller == address(0)) caller = LibMulticaller.sender();
        _;
        caller = address(0);
    }

    modifier notPaused() {
        IProtocolState(ADDRESS_REGISTRY.getProtocolState()).requireNotStopped();
        _;
    }

    /// @notice this variable is transient
    address internal caller;

    IProtocolAddressRegistry internal immutable ADDRESS_REGISTRY;

    constructor(IProtocolAddressRegistry _addressRegistry) {
        ADDRESS_REGISTRY = _addressRegistry;
    }

    function isTokenWhitelisted(address user, address token) public view returns (bool) {
        return ITokenWhitelistRegistry(ADDRESS_REGISTRY.getTokenWhitelistRegistry())
            .isTokenWhitelisted(user, address(this), token);
    }

    function _checkTokenIsWhitelisted(address user, address token) internal view {
        if (!isTokenWhitelisted(user, token)) revert TokenNotWhitelisted();
    }

    function _checkTokensAreWhitelisted(address user, bytes memory packedTokens) internal view {
        address[] memory tokens = packedTokens.unpackAddresses();

        uint256 length = tokens.length;

        require(length > 0, "Router: length must be > 0");

        for (uint256 i = 0; i < length;) {
            _checkTokenIsWhitelisted(user, tokens[i]);

            unchecked {
                ++i;
            }
        }
    }
}
