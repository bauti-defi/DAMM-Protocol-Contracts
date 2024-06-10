// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// string constant HookNotDefined_Error = "Hooks are not defined";
// string constant InvalidTransactionLength_Error = "Invalid transaction length";
// string constant GasLimitExceeded_Error = "Gas limit exceeded";
// string constant GasRefundFailed_Error = "Gas refund failed";
// string constant OnlyFund_Error = "only fund";
// string constant Paused_Error = "trading module paused";

library Errors {
    error HookNotDefined();
    error InvalidTransactionLength();
    error GasLimitExceeded();
    error GasRefundFailed();
    error OnlyFund();
    error ModulePaused();
}
