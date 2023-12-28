// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IRouter} from "@src/interfaces/IRouter.sol";
import {ReentrancyGuard} from "@src/lib/ReentrancyGuard.sol";
import {ITokenWhitelistRegistry} from "@src/interfaces/ITokenWhitelistRegistry.sol";
import {LibMulticaller} from "@vec-multicaller/LibMulticaller.sol";

abstract contract BaseRouter is IRouter, ReentrancyGuard {
    modifier setCaller() {
        if (caller == address(0)) caller = LibMulticaller.sender();
        _;
        caller = address(0);
    }

    /// @notice this variable is transient
    address internal caller;

    ITokenWhitelistRegistry public immutable tokenWhitelistRegistry;
    address public immutable owner;
    address public immutable multicallerWithSender;

    constructor(address _owner, address _tokenWhitelistRegistry, address _multicallerWithSender) {
        owner = _owner;
        multicallerWithSender = _multicallerWithSender;
        tokenWhitelistRegistry = ITokenWhitelistRegistry(_tokenWhitelistRegistry);
    }

    function isTokenWhitelisted(address user, address token) public view returns (bool) {
        return tokenWhitelistRegistry.isTokenWhitelisted(user, address(this), token);
    }

    function _checkTokenIsWhitelisted(address user, address token) internal view {
        if (!isTokenWhitelisted(user, token)) revert TokenNotWhitelisted();
    }

    fallback() external payable {
        revert("Router: invalid fallback");
    }

    // @notice To receive ETH from WETH and NFT protocols
    receive() external payable {}
}
