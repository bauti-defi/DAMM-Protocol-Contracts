// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {ITokenWhitelistRegistry} from "@src/interfaces/ITokenWhitelistRegistry.sol";
import {LibMulticaller} from "@vec-multicaller/LibMulticaller.sol";
import {IWETH9} from "@src/interfaces/external/IWETH9.sol";
import {TransferHelper} from "@src/lib/TransferHelper.sol";
import {IProtocolState} from "@src/interfaces/IProtocolState.sol";
import {Pausable} from "@src/base/Pausable.sol";

abstract contract BaseRouter is Pausable {
    error InvalidRecipient();
    error TokenNotWhitelisted();

    modifier setCaller() {
        if (caller == address(0)) caller = LibMulticaller.sender();
        _;
        caller = address(0);
    }

    /// @notice this variable is transient
    address internal caller;

    IProtocolState public immutable protocolState;
    ITokenWhitelistRegistry public immutable tokenWhitelistRegistry;
    address public immutable multicallerWithSender;
    address public immutable WETH9;

    constructor(address _protocolState, address _WETH9, address _tokenWhitelistRegistry, address _multicallerWithSender)
        Pausable(_protocolState)
    {
        protocolState = IProtocolState(_protocolState);
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

    function _checkTokensAreWhitelisted(address user, address[] memory tokens) internal view {
        uint256 length = tokens.length;

        require(length > 0, "Router: length must be > 0");

        for (uint256 i = 0; i < length;) {
            _checkTokenIsWhitelisted(user, tokens[i]);

            unchecked {
                ++i;
            }
        }
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
