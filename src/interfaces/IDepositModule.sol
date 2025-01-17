// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {
    SignedWithdrawIntent,
    DepositOrder,
    SignedDepositIntent,
    WithdrawOrder
} from "@src/modules/deposit/Structs.sol";
import {IPausable} from "@src/interfaces/IPausable.sol";

interface IDepositModule is IPausable {
    function periphery() external view returns (address);
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
}
