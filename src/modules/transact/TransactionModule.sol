// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {ISafe} from "@src/interfaces/ISafe.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import "@solady/utils/ReentrancyGuard.sol";
import "@src/libs/Errors.sol";
import "@src/interfaces/ITransactionHooks.sol";
import "@src/interfaces/ITransactionModule.sol";
import "./Structs.sol";
import {BP_DIVISOR} from "@src/libs/Constants.sol";
import {SafeLib} from "@src/libs/SafeLib.sol";
import {IFund} from "@src/interfaces/IFund.sol";
import {Pausable} from "@src/core/Pausable.sol";

/// @title Transaction Module
/// @notice A Safe module that executes transactions with hook-based validation
/// @dev Supports multicall execution with before/after hooks and gas refunds
contract TransactionModule is ReentrancyGuard, Pausable, ITransactionModule {
    using SafeLib for ISafe;

    /// @inheritdoc ITransactionModule
    address public immutable fund;
    /// @inheritdoc ITransactionModule
    IHookRegistry public immutable hookRegistry;

    /// @notice Ensures caller is the fund contract
    modifier onlyFund() {
        if (msg.sender != fund) revert Errors.OnlyFund();
        _;
    }

    /// @notice Refunds gas costs to the transaction caller
    /// @dev Refund will not be exact but approximates actual gas used
    modifier refundGasToCaller() {
        uint256 gasAtStart = gasleft();

        _;

        if (
            /// the refund will not be exact but we can get close
            !ISafe(fund).execTransactionFromModule(
                msg.sender, (gasAtStart - gasleft()) * tx.gasprice, "", Enum.Operation.Call
            )
        ) {
            revert Errors.Transaction_GasRefundFailed();
        }
    }

    /// @notice Creates a new transaction module
    /// @param owner The fund contract address
    /// @param _hookRegistry The hook registry contract address
    constructor(address owner, address _hookRegistry) Pausable(owner) {
        fund = owner;
        hookRegistry = IHookRegistry(_hookRegistry);
    }

    /// @inheritdoc ITransactionModule
    function execute(Transaction[] calldata transactions)
        external
        nonReentrant
        refundGasToCaller
        notPaused
    {
        uint256 transactionCount = transactions.length;

        /// @notice there must be at least one transaction
        if (transactionCount == 0) revert Errors.Transaction_InvalidTransactionLength();

        /// lets iterate over the transactions. Each transaction will be verified and then executed through the safe.
        for (uint256 i = 0; i < transactionCount;) {
            /// msg.sender is operator
            Hooks memory hook = hookRegistry.getHooks(
                msg.sender, // operator
                transactions[i].target,
                transactions[i].operation,
                transactions[i].targetSelector
            );

            if (!hook.defined) {
                revert Errors.Transaction_HookNotDefined();
            }

            if (hook.beforeTrxHook != address(0)) {
                ISafe(fund).executeAndReturnDataOrRevert(
                    /// target
                    hook.beforeTrxHook,
                    /// value
                    0,
                    /// data
                    abi.encodeWithSelector(
                        IBeforeTransaction.checkBeforeTransaction.selector,
                        transactions[i].target,
                        transactions[i].targetSelector,
                        transactions[i].operation,
                        transactions[i].value,
                        transactions[i].data
                    ),
                    /// operation
                    Enum.Operation.Call
                );
            }

            bytes memory returnData = ISafe(fund).executeAndReturnDataOrRevert(
                transactions[i].target,
                transactions[i].value,
                abi.encodePacked(transactions[i].targetSelector, transactions[i].data),
                transactions[i].operation == uint8(Enum.Operation.DelegateCall)
                    ? Enum.Operation.DelegateCall
                    : Enum.Operation.Call
            );

            if (hook.afterTrxHook != address(0)) {
                ISafe(fund).executeAndReturnDataOrRevert(
                    hook.afterTrxHook,
                    0,
                    abi.encodeWithSelector(
                        IAfterTransaction.checkAfterTransaction.selector,
                        transactions[i].target,
                        transactions[i].targetSelector,
                        transactions[i].operation,
                        transactions[i].value,
                        transactions[i].data,
                        returnData
                    ),
                    Enum.Operation.Call
                );
            }

            unchecked {
                ++i;
            }
        }
    }
}
