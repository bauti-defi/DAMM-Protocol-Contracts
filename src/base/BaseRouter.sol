// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IRouter} from "@src/interfaces/IRouter.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@src/lib/ReentrancyGuard.sol";
import {IMulticall} from "@src/interfaces/IMulticall.sol";
import {ITokenWhitelistRegistry} from "@src/interfaces/ITokenWhitelistRegistry.sol";

abstract contract BaseRouter is IRouter, ReentrancyGuard {
    modifier setCaller() {
        if (caller == address(0)) {
            if(msg.sender == multicallerWithSender) {
                // caller = IMulticall(msg.sender).caller();
            } else {
                caller = msg.sender;
            }
        }
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
