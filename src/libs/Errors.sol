// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

/// @dev Protocol errors
library Errors {
    /// Shared errors
    /// @notice Thrown when a function can only be called by the fund itself
    error OnlyFund();
    /// @notice Thrown when a function can only be called by an admin
    error OnlyAdmin();
    /// @notice Thrown when an asset transfer fails
    error AssetTransferFailed();
    /// @notice Thrown when trying to execute a function while the contract is paused
    error Paused();
    /// @notice Thrown when a function must be called via delegatecall
    error OnlyDelegateCall();

    /// Transaction module errors
    /// @notice Thrown when a transaction hook is not defined for a given operation
    error Transaction_HookNotDefined();
    /// @notice Thrown when a transaction's data length is invalid
    error Transaction_InvalidTransactionLength();
    /// @notice Thrown when a transaction exceeds its gas limit
    error Transaction_GasLimitExceeded();
    /// @notice Thrown when gas refund to the caller fails
    error Transaction_GasRefundFailed();
    /// @notice Thrown when trying to execute a transaction while the module is paused
    error Transaction_ModulePaused();

    /// Hook errors
    /// @notice Thrown when an operator is not authorized to execute a hook
    error Hook_InvalidOperator();
    /// @notice Thrown when a hook's target address is invalid
    error Hook_InvalidTargetAddress();
    /// @notice Thrown when a before-execution hook is invalid
    error Hook_InvalidBeforeHook();
    /// @notice Thrown when an after-execution hook is invalid
    error Hook_InvalidAfterHook();
    /// @notice Thrown when a hook's value parameter is invalid
    error Hook_InvalidValue();
    /// @notice Thrown when a hook's operation type is invalid
    error Hook_InvalidOperation();
    /// @notice Thrown when a hook's target function selector is invalid
    error Hook_InvalidTargetSelector();
    /// @notice Thrown when attempting to define a hook that already exists
    error Hook_AlreadyDefined();
    /// @notice Thrown when attempting to use a hook that hasn't been defined
    error Hook_NotDefined();

    /// Constructor errors
    /// @notice Thrown when a constructor parameter is invalid
    error Deposit_InvalidConstructorParam();

    /// Signature errors
    /// @notice Thrown when a signature verification fails
    error Deposit_InvalidSignature();
    /// @notice Thrown when a transaction nonce is invalid
    error Deposit_InvalidNonce();
    /// @notice Thrown when an order has expired
    error Deposit_OrderExpired();
    /// @notice Thrown when executing on an invalid chain ID
    error Deposit_InvalidChain();

    /// Amount errors
    /// @notice Thrown when an asset amount is insufficient for the operation
    error Deposit_InsufficientAmount();
    /// @notice Thrown when an asset deposit amount is insufficient
    error Deposit_InsufficientDeposit();
    /// @notice Thrown when an asset withdrawal amount is insufficient
    error Deposit_InsufficientWithdrawal();
    /// @notice Thrown when slippage exceeds the allowed limit
    error Deposit_SlippageLimitExceeded();
    /// @notice Thrown when share minting would exceed the allowed limit
    error Deposit_ShareMintLimitExceeded();
    /// @notice Thrown when share burning would exceed the allowed limit
    error Deposit_ShareBurnLimitExceeded();
    /// @notice Thrown when share minting would result in zero or insufficient shares
    error Deposit_InsufficientShares();

    /// Asset policy errors
    /// @notice Thrown when an asset policy is invalid
    error Deposit_InvalidAssetPolicy();

    /// Asset errors
    /// @notice Thrown when an asset is temporarily unavailable
    error Deposit_AssetUnavailable();
    /// @notice Thrown when an asset is not supported by the protocol
    error Deposit_AssetNotSupported();

    /// Account errors
    /// @notice Thrown when attempting to pause an already paused account
    error Deposit_AccountNotPaused();
    /// @notice Thrown when an account is not in active status
    error Deposit_AccountNotActive();
    /// @notice Thrown when attempting to operate on a non-existent account
    error Deposit_AccountDoesNotExist();
    /// @notice Thrown when an account has expired
    error Deposit_AccountExpired();
    /// @notice Thrown when attempting to transfer a non-transferable account
    error Deposit_AccountNotTransferable();
    /// @notice Thrown when an account cannot be closed
    error Deposit_AccountCannotBeClosed();

    /// Access control errors
    /// @notice Thrown when a function can only be called by the user
    error Deposit_OnlyUser();
    /// @notice Thrown when a function can only be called by a super user
    error Deposit_OnlySuperUser();
    /// @notice Thrown when a function can only be called by the periphery contract
    error Deposit_OnlyPeriphery();
    /// @notice Thrown when a function can only be called by the account owner
    error Deposit_OnlyAccountOwner();

    /// parameter errors
    /// @notice Thrown when a performance fee parameter is invalid
    error Deposit_InvalidPerformanceFee();
    /// @notice Thrown when an entrance fee parameter is invalid
    error Deposit_InvalidEntranceFee();
    /// @notice Thrown when an exit fee parameter is invalid
    error Deposit_InvalidExitFee();
    /// @notice Thrown when a protocol fee recipient address is invalid
    error Deposit_InvalidProtocolFeeRecipient();
    /// @notice Thrown when a management fee rate is invalid
    error Deposit_InvalidManagementFeeRate();
    /// @notice Thrown when a role parameter is invalid
    error Deposit_InvalidRole();
    /// @notice Thrown when a time-to-live parameter is invalid
    error Deposit_InvalidTTL();
    /// @notice Thrown when a share mint limit parameter is invalid
    error Deposit_InvalidShareMintLimit();
    /// @notice Thrown when a broker fee recipient address is invalid
    error Deposit_InvalidBrokerFeeRecipient();

    /// Admin errors
    /// @notice Thrown when an admin address is invalid
    error Deposit_InvalidAdmin();
    /// @notice Thrown when a user address is invalid
    error Deposit_InvalidUser();

    /// ModuleLib errors
    /// @notice Thrown when module deployment fails
    error ModuleLib_DeploymentFailed();
    /// @notice Thrown when module setup fails after deployment
    error ModuleLib_ModuleSetupFailed();
    /// @notice Thrown when there's insufficient balance for module deployment
    error ModuleLib_InsufficientBalance();
    /// @notice Thrown when attempting to deploy a module with empty bytecode
    error ModuleLib_EmptyBytecode();

    /// FundCallbackHandler errors
    /// @notice Thrown when a caller is not a registered module
    error Fund_NotModule();
    /// @notice Thrown when a caller is not authorized to perform an action
    error Fund_NotAuthorized();
    /// @notice Thrown when the fund liquidation time series is empty
    error Fund_EmptyFundLiquidationTimeSeries();

    /// FundFactory errors
    /// @notice Thrown when the deployment lock is violated
    error FundFactory_DeploymentLockViolated();
    /// @notice Thrown when a function must be called via delegatecall
    error FundFactory_OnlyDelegateCall();

    /// FundValuationOracle
    /// @notice Thrown when attempting to value a fund that is not fully divested
    error FundValuationOracle_FundNotFullyDivested();
}
