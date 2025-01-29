// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "./DepositModule.sol";
import "@openzeppelin-contracts/access/AccessControl.sol";

bytes32 constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
bytes32 constant USER_ROLE = keccak256("USER_ROLE");

/// @title Whitelist Deposit Module Interface
/// @notice A Gnosis Safe module that restricts deposits/withdrawals to whitelisted users
/// @dev Extends DepositModule to add whitelist functionality
///      Only whitelisted users can deposit/withdraw through this module
///      The safe must have a valid broker account (nft) from the periphery
contract WhitelistDepositModule is DepositModule, AccessControl {
    /// @notice Creates a new whitelist deposit module
    /// @param fund_ The fund contract address
    /// @param safe_ The Gnosis Safe address
    /// @param periphery_ The periphery contract address
    constructor(address fund_, address safe_, address periphery_)
        DepositModule(fund_, safe_, periphery_)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, fund_);
    }

    modifier onlyWhitelisted(address user_) {
        _checkRole(USER_ROLE, user_);
        _;
    }

    /// @inheritdoc IDepositModule
    function deposit(DepositOrder calldata order)
        external
        onlyWhitelisted(msg.sender)
        returns (uint256 sharesOut)
    {
        sharesOut = _deposit(order);
    }

    /// @inheritdoc IDepositModule
    function intentDeposit(SignedDepositIntent calldata order)
        external
        onlyWhitelisted(order.intent.deposit.recipient)
        returns (uint256 sharesOut)
    {
        sharesOut = _intentDeposit(order);
    }

    /// @inheritdoc IDepositModule
    function withdraw(WithdrawOrder calldata order)
        external
        onlyWhitelisted(msg.sender)
        returns (uint256 assetAmountOut)
    {
        assetAmountOut = _withdraw(order);
    }

    /// @inheritdoc IDepositModule
    function intentWithdraw(SignedWithdrawIntent calldata order)
        external
        onlyWhitelisted(order.intent.withdraw.to)
        returns (uint256 assetAmountOut)
    {
        assetAmountOut = _intentWithdraw(order);
    }
}
