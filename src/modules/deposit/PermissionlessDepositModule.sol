// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "./DepositModule.sol";

/// @title Permissionless Deposit Module
/// @notice A Gnosis Safe module that allows anyone to deposit/withdraw through the fund
/// @dev A module that when added to a gnosis safe, allows for anyone to deposit into the fund
///      The gnosis safe must have a valid broker account (nft) with the periphery to be able to deposit
///      on behalf of the caller.
///      Any user can deposit/withdraw through this module without restrictions
contract PermissionlessDepositModule is DepositModule {
    /// @inheritdoc IDepositModule
    function deposit(DepositOrder calldata order) external virtual returns (uint256 sharesOut) {
        sharesOut = _deposit(order);
    }

    /// @inheritdoc IDepositModule
    function intentDeposit(SignedDepositIntent calldata order)
        external
        virtual
        returns (uint256 sharesOut)
    {
        sharesOut = _intentDeposit(order);
    }

    /// @inheritdoc IDepositModule
    function withdraw(WithdrawOrder calldata order)
        external
        virtual
        returns (uint256 assetAmountOut)
    {
        assetAmountOut = _withdraw(order);
    }

    /// @inheritdoc IDepositModule
    function intentWithdraw(SignedWithdrawIntent calldata order)
        external
        virtual
        returns (uint256 assetAmountOut)
    {
        assetAmountOut = _intentWithdraw(order);
    }
}
