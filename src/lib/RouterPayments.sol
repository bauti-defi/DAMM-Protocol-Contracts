// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {IWETH9} from "@src/interfaces/external/IWETH9.sol";
import "@src/lib/GPv2SafeERC20.sol";
import "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract RouterPayments {
    using GPv2SafeERC20 for IERC20;

    IWETH9 internal immutable WETH9;

    constructor(IWETH9 _WETH9) {
        WETH9 = _WETH9;
    }

    function safelyEnsureTokenAllowance(address token, address to, uint256 allowanceRequired)
        internal
    {
        IERC20 tokenToApprove = IERC20(token);

        if (tokenToApprove.allowance(address(this), to) < allowanceRequired) {
            SafeERC20.forceApprove(tokenToApprove, to, type(uint256).max);
        }
    }

    /// @notice Transfers the full amount of a token held by this contract to recipient
    /// @dev The amountMinimum parameter prevents malicious contracts from stealing the token from users
    /// @param token The contract address of the token which will be transferred to `recipient`
    /// @param amountMinimum The minimum amount of token required for a transfer
    /// @param recipient The destination address of the token
    function sweepToken(address token, uint256 amountMinimum, address recipient) public payable {
        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        require(balanceToken >= amountMinimum, "Insufficient token");

        if (balanceToken > 0) {
            IERC20(token).safeTransfer(recipient, balanceToken);
        }
    }

    receive() external payable {
        require(msg.sender == address(WETH9), "Not WETH9");
    }

    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The entity that will receive payment
    /// @param value The amount to pay
    function transfer(address token, address payer, address recipient, uint256 value) internal {
        if (token == address(WETH9) && address(this).balance >= value) {
            // pay with WETH9
            WETH9.deposit{value: value}(); // wrap only what is needed to pay
            WETH9.transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            IERC20(token).safeTransfer(recipient, value);
        } else {
            // pull payment
            IERC20(token).safeTransferFrom(payer, recipient, value);
        }
    }
}
