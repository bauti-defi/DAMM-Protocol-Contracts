// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "./DepositModule.sol";

/// @dev A module that when added to a gnosis safe, allows for anyone to deposit into the fund
/// the gnosis safe must have a valid broker account (nft) with the periphery to be able to deposit
/// on behalf of the caller.
contract PermissionlessDepositModule is DepositModule {
    constructor(address fund_, address safe_, address periphery_)
        DepositModule(fund_, safe_, periphery_)
    {}

    function deposit(DepositOrder calldata order) external virtual returns (uint256 sharesOut) {
        sharesOut = _deposit(order);
    }

    function intentDeposit(SignedDepositIntent calldata order)
        external
        virtual
        returns (uint256 sharesOut)
    {
        sharesOut = _intentDeposit(order);
    }

    function withdraw(WithdrawOrder calldata order)
        external
        virtual
        returns (uint256 assetAmountOut)
    {
        assetAmountOut = _withdraw(order);
    }

    function intentWithdraw(SignedWithdrawIntent calldata order)
        external
        virtual
        returns (uint256 assetAmountOut)
    {
        assetAmountOut = _intentWithdraw(order);
    }
}
