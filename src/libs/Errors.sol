// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @dev Protocol errors
library Errors {
    /// Shared errors
    error OnlyFund();

    /// Trading module errors
    error TransactionModule_HookNotDefined();
    error TransactionModule_InvalidTransactionLength();
    error TransactionModule_GasLimitExceeded();
    error TransactionModule_GasRefundFailed();
    error Trading_ModulePaused();

    /// Hook errors
    error Hook_InvalidOperator();
    error Hook_InvalidTargetAddress();
    error Hook_InvalidBeforeHookAddress();
    error Hook_InvalidAfterHookAddress();
    error Hook_InvalidOperation();

    /// Signature errors
    error Deposit_InvalidSignature();
    error Deposit_InvalidNonce();
    error Deposit_IntentExpired();
    error Deposit_InvalidChain();

    /// Amount errors
    error Deposit_InsufficientAmount();
    error Deposit_InsufficientDeposit();
    error Deposit_InsufficientWithdrawal();
    error Deposit_SlippageLimitExceeded();

    /// Supply invariant errors
    error Deposit_SupplyInvariantViolated();
    error Deposit_FundNotFullyDivested();
    error Deposit_AssetInvariantViolated();

    /// Asset policy errors
    error Deposit_InvalidAssetPolicy();

    /// Asset errors
    error Deposit_AssetTransferFailed();
    error Deposit_AssetUnavailable();
    error Deposit_AssetNotSupported();

    /// Account errors
    error Deposit_AccountNotPaused();
    error Deposit_AccountNotActive();
    error Deposit_AccountExists();

    /// Access control errors
    error Deposit_OnlyFeeRecipient();
    error Deposit_OnlyUser();
    error Deposit_OnlySuperUser();
    error Deposit_OnlyPeriphery();

    /// Fee errors
    error Deposit_InvalidPerformanceFee();
    error Deposit_InvalidFeeRecipient();

    /// Module errors
    error Deposit_ModulePaused();

    /// ModuleLib errors
    error ModuleLib_DeploymentFailed();
    error ModuleLib_ModuleSetupFailed();
    error ModuleLib_InsufficientBalance();
    error ModuleLib_EmptyBytecode();
    error ModuleLib_OnlyDelegateCall();
}
