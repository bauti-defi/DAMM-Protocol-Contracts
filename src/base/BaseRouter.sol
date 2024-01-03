// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IRouter} from "@src/interfaces/IRouter.sol";
import {ITokenWhitelistRegistry} from "@src/interfaces/ITokenWhitelistRegistry.sol";
import {LibMulticaller} from "@vec-multicaller/LibMulticaller.sol";
import {IWETH9} from "@src/interfaces/external/IWETH9.sol";
import {TransferHelper} from "@src/lib/TransferHelper.sol";
import {ProtocolStateAccesor} from "@src/lib/ProtocolStateAccesor.sol";

abstract contract BaseRouter is ProtocolStateAccesor, IRouter {
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
    address public immutable WETH9;

    constructor(
        address _owner,
        address _protocolState,
        address _WETH9,
        address _tokenWhitelistRegistry,
        address _multicallerWithSender
    ) ProtocolStateAccesor(_protocolState) {
        owner = _owner;
        WETH9 = _WETH9;
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

    receive() external payable {
        require(msg.sender == WETH9, "Not WETH9");
    }

    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The entity that will receive payment
    /// @param value The amount to pay
    function transfer(address token, address payer, address recipient, uint256 value) internal {
        if (token == WETH9 && address(this).balance >= value) {
            // pay with WETH9
            IWETH9(WETH9).deposit{value: value}(); // wrap only what is needed to pay
            IWETH9(WETH9).transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }
}
