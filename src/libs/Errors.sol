// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @dev Protocol errors
library Errors {
    /// Shared errors
    error OnlyFund();

    /// Transaction module errors
    error Transaction_HookNotDefined();
    error Transaction_InvalidTransactionLength();
    error Transaction_GasLimitExceeded();
    error Transaction_GasRefundFailed();
    error Transaction_ModulePaused();

    /// Hook errors
    error Hook_InvalidOperator();
    error Hook_InvalidTargetAddress();
    error Hook_InvalidBeforeHookAddress();
    error Hook_InvalidAfterHookAddress();
    error Hook_InvalidValue();
    error Hook_InvalidOperation();
    error Hook_InvalidTargetSelector();

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
    error Deposit_InvalidAccountRoleUpdate();
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

    /// FundCallbackHandler errors
    error Fund_NotModule();
    error Fund_NotAuthorized();
    error Fund_EmptyFundLiquidationTimeSeries();

    /// FundFactory errors
    error FundFactory_DeploymentLockViolated();

    /// FundValuationOracle
    error FundValuationOracle_FundNotFullyDivested();
}
