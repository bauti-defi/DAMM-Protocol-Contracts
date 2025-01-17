// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "./DepositModule.sol";

event UserAddedToWhitelist(address user_);

event UserRemovedFromWhitelist(address user_);

/// @dev A module that when added to a gnosis safe, allows for any whitelisted user to deposit into the fund
/// the gnosis safe must have a valid broker account (nft) with the periphery to be able to deposit
/// on behalf of the caller.
contract WhitelistDepositModule is DepositModule {
    mapping(address user => bool allowed) public userWhitelist;

    constructor(address fund_, address safe_, address periphery_)
        DepositModule(fund_, safe_, periphery_)
    {}

    modifier onlyWhitelisted(address user_) {
        if (!userWhitelist[user_]) revert Errors.OnlyWhitelisted();
        _;
    }

    function addUserToWhitelist(address user_) external onlyAdmin {
        userWhitelist[user_] = true;

        emit UserAddedToWhitelist(user_);
    }

    function removeUserFromWhitelist(address user_) external onlyAdmin {
        userWhitelist[user_] = false;

        emit UserRemovedFromWhitelist(user_);
    }

    function deposit(DepositOrder calldata order)
        external
        onlyWhitelisted(msg.sender)
        returns (uint256 sharesOut)
    {
        sharesOut = _deposit(order);
    }

    function intentDeposit(SignedDepositIntent calldata order)
        external
        onlyWhitelisted(order.intent.deposit.recipient)
        returns (uint256 sharesOut)
    {
        sharesOut = _intentDeposit(order);
    }

    function withdraw(WithdrawOrder calldata order)
        external
        onlyWhitelisted(msg.sender)
        returns (uint256 assetAmountOut)
    {
        assetAmountOut = _withdraw(order);
    }

    function intentWithdraw(SignedWithdrawIntent calldata order)
        external
        onlyWhitelisted(order.intent.withdraw.to)
        returns (uint256 assetAmountOut)
    {
        assetAmountOut = _intentWithdraw(order);
    }
}
