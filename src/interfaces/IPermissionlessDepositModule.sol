// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {
    SignedWithdrawIntent,
    DepositOrder,
    SignedDepositIntent,
    WithdrawOrder
} from "@src/modules/deposit/Structs.sol";

interface IPermissionlessDepositModule {
    event Paused();

    event Unpaused();

    function periphery() external view returns (address);
    function paused() external view returns (bool);
    function nonces(address user) external view returns (uint256);
    function safe() external view returns (address);
    function withdraw(WithdrawOrder calldata order) external returns (uint256 assetAmountOut);
    function intentWithdraw(SignedWithdrawIntent calldata order)
        external
        returns (uint256 assetAmountOut);
    function deposit(DepositOrder calldata order) external returns (uint256 sharesOut);
    function intentDeposit(SignedDepositIntent calldata order)
        external
        returns (uint256 sharesOut);
    function increaseNonce(uint256 increment_) external;
    function pause() external;
    function unpause() external;
}
