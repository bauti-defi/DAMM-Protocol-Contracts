// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Role} from "./Structs.sol";

event AssetEnabled(address asset);

event AssetDisabled(address asset);

event AccountOpened(address indexed user, Role role);

event AccountRoleChanged(address indexed user, Role role);

event AccountPaused(address indexed user);

event AccountUnpaused(address indexed user);

event FeeRecipientUpdated(address newRecipient, address oldRecipient);

event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);

event Deposit(
    address indexed user,
    address asset,
    uint256 assetAmountIn,
    uint256 sharesOut,
    address relayer,
    uint256 relayerTip
);

event Withdraw(
    address indexed user,
    address to,
    address asset,
    uint256 sharesIn,
    uint256 assetAmountOut,
    address relayer,
    uint256 relayerTip
);

event WithdrawFees(address indexed to, address asset, uint256 sharesIn, uint256 assetAmountOut);
