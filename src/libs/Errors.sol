// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @dev Protocol errors
library Errors {
    /// Shared errors
    error OnlyFund();
    error OnlyAdmin();

    /// Transaction module errors
    error Transaction_HookNotDefined();
    error Transaction_InvalidTransactionLength();
    error Transaction_GasLimitExceeded();
    error Transaction_GasRefundFailed();
    error Transaction_ModulePaused();

    /// Hook errors
    error Hook_InvalidOperator();
    error Hook_InvalidTargetAddress();
    error Hook_InvalidBeforeHook();
    error Hook_InvalidAfterHook();
    error Hook_InvalidValue();
    error Hook_InvalidOperation();
    error Hook_InvalidTargetSelector();
    error Hook_AlreadyDefined();

    /// Constructor errors
    error Deposit_InvalidConstructorParam();

    /// Signature errors
    error Deposit_InvalidSignature();
    error Deposit_InvalidNonce();
    error Deposit_OrderExpired();
    error Deposit_InvalidChain();

    /// Amount errors
    error Deposit_InsufficientAmount();
    error Deposit_InsufficientDeposit();
    error Deposit_InsufficientWithdrawal();
    error Deposit_SlippageLimitExceeded();
    error Deposit_ShareMintLimitExceeded();
    error Deposit_ShareBurnLimitExceeded();

    /// Asset policy errors
    error Deposit_InvalidAssetPolicy();

    /// Asset errors
    error Deposit_AssetTransferFailed();
    error Deposit_AssetUnavailable();
    error Deposit_AssetNotSupported();

    /// Account errors
    error Deposit_AccountNotPaused();
    error Deposit_AccountNotActive();
    error Deposit_AccountDoesNotExist();
    error Deposit_AccountExpired();
    error Deposit_AccountNotTransferable();
    error Deposit_AccountCannotBeClosed();

    /// Access control errors
    error Deposit_OnlyUser();
    error Deposit_OnlySuperUser();
    error Deposit_OnlyPeriphery();
    error Deposit_OnlyAccountOwner();

    /// parameter errors
    error Deposit_InvalidPerformanceFee();
    error Deposit_InvalidFeeRecipient();
    error Deposit_InvalidRole();
    error Deposit_InvalidTTL();
    error Deposit_InvalidShareMintLimit();

    /// Admin errors
    error Deposit_InvalidAdmin();
    error Deposit_InvalidUser();

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
    error FundFactory_OnlyDelegateCall();

    /// FundValuationOracle
    error FundValuationOracle_FundNotFullyDivested();
}
