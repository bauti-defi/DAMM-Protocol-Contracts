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
import "@openzeppelin-contracts/access/AccessControl.sol";
import "@openzeppelin-contracts/utils/Pausable.sol";

/// @title Transaction Module
/// @notice A Safe module that executes transactions with hook-based validation
/// @dev Supports multicall execution with before/after hooks and gas refunds
contract TransactionModule is AccessControl, Pausable, ReentrancyGuard, ITransactionModule {
    using SafeLib for ISafe;

    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 constant FUND_ROLE = keccak256("FUND_ROLE");

    /// @inheritdoc ITransactionModule
    address public immutable fund;
    /// @inheritdoc ITransactionModule
    IHookRegistry public immutable hookRegistry;

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
    /// @param _fund The fund contract address
    /// @param _hookRegistry The hook registry contract address
    constructor(address _fund, address _hookRegistry) Pausable() {
        fund = _fund;
        hookRegistry = IHookRegistry(_hookRegistry);

        _grantRole(DEFAULT_ADMIN_ROLE, _fund);
        _grantRole(FUND_ROLE, _fund);
        _grantRole(PAUSER_ROLE, _fund);
    }

    /// @inheritdoc ITransactionModule
    function execute(Transaction[] calldata transactions)
        external
        nonReentrant
        whenNotPaused
        refundGasToCaller
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

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function setPauser(address _pauser) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PAUSER_ROLE, _pauser);
    }

    function revokePauser(address _pauser) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(PAUSER_ROLE, _pauser);
    }
}
