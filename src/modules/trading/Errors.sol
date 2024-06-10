// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Errors {
    error HookNotDefined();
    error InvalidTransactionLength();
    error GasLimitExceeded();
    error GasRefundFailed();
    error OnlyFund();
    error ModulePaused();
}
