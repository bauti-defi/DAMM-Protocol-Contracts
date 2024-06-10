// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Errors {
    /// Trading module errors
    error TradingModule_HookNotDefined();
    error TradingModule_InvalidTransactionLength();
    error TradingModule_GasLimitExceeded();
    error TradingModule_GasRefundFailed();
    error TradingModule_Paused();

    /// Hook errors
    error Hook_InvalidOperator();
    error Hook_InvalidTargetAddress();
    error Hook_InvalidBeforeHookAddress();
    error Hook_InvalidAfterHookAddress();
    error Hook_InvalidOperation();

    /// shared errors
    error OnlyFund();
}
