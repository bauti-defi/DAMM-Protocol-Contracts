// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {ISafe} from "@src/interfaces/ISafe.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {ITradingModule} from "@src/interfaces/ITradingModule.sol";
import {IBeforeTransaction, IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";

library HookLib {
    function pointer(ITradingModule.HookConfig memory config) internal pure returns (bytes32) {
        return hookPointer(config.operator, config.target, config.operation, config.targetSelector);
    }

    function checkConfigIsValid(ITradingModule.HookConfig memory config, address fund)
        internal
        view
    {
        require(config.operator != address(0), "operator is zero address");
        require(config.operator != fund, "operator is fund");
        require(config.operator != address(this), "operator is self");

        require(config.target != address(0), "target is zero address");
        require(config.target != address(this), "target is self");

        require(config.beforeTrxHook != address(this), "beforeTrxHook is self");
        require(config.beforeTrxHook != config.operator, "beforeTrxHook is operator");

        require(config.afterTrxHook != address(this), "afterTrxHook is self");
        require(config.afterTrxHook != config.operator, "afterTrxHook is operator");

        require(config.targetSelector != bytes4(0), "target selector is zero");
        // only 0 or 1 allowed (0 = call, 1 = delegatecall)
        require(
            config.operation == uint8(Enum.Operation.Call)
                || config.operation == uint8(Enum.Operation.DelegateCall),
            "operation is invalid"
        );
    }

    function hookPointer(address operator, address target, uint8 operation, bytes4 selector)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(operator, target, operation, selector));
    }
}

contract TradingModule is ITradingModule, ReentrancyGuard {
    using HookLib for ITradingModule.HookConfig;

    address public immutable fund;
    bool public paused;

    // keccak256(abi.encode(operator, target, operation, selector)) => hooks
    // bytes20 + bytes20 + bytes8 + bytes4 = 52 bytes
    mapping(bytes32 hookPointer => Hooks) private hooks;

    modifier onlyFund() {
        require(msg.sender == fund, "only fund");
        _;
    }

    modifier notPaused() {
        require(paused == false, "paused");
        _;
    }

    constructor(address owner) {
        fund = owner;
    }

    function _setHooks(HookConfig calldata config) internal notPaused {
        config.checkConfigIsValid(fund);

        bytes32 pointer = config.pointer();

        hooks[pointer] = Hooks({
            beforeTrxHook: config.beforeTrxHook,
            afterTrxHook: config.afterTrxHook,
            defined: true
        });

        emit HookSet(pointer);
    }

    function batchSetHooks(HookConfig[] calldata configs) external onlyFund {
        uint256 length = configs.length;
        for (uint256 i = 0; i < length;) {
            _setHooks(configs[i]);

            unchecked {
                ++i;
            }
        }
    }

    function getHooks(address operator, address target, uint8 operation, bytes4 selector)
        external
        view
        returns (Hooks memory)
    {
        return hooks[HookLib.hookPointer(operator, target, operation, selector)];
    }

    function setHooks(HookConfig calldata config) external onlyFund {
        _setHooks(config);
    }

    function _removeHooks(address operator, address target, uint8 operation, bytes4 selector)
        internal
    {
        delete hooks[HookLib.hookPointer(operator, target, operation, selector)];

        emit HookRemoved(operator, target, operation, selector);
    }

    function batchRemoveHooks(HookConfig[] calldata configs) external onlyFund {
        uint256 length = configs.length;
        for (uint256 i = 0; i < length;) {
            _removeHooks(
                configs[i].operator,
                configs[i].target,
                configs[i].operation,
                configs[i].targetSelector
            );

            unchecked {
                ++i;
            }
        }
    }

    function removeHooks(HookConfig calldata config) external onlyFund {
        _removeHooks(config.operator, config.target, config.operation, config.targetSelector);
    }

    /**
     * @dev Sends multiple transactions and reverts all if one fails.
     * @param transactions Encoded transactions. Each transaction is encoded as a packed bytes of
     *                     operation as a uint8 with 0 for a call or 1 for a delegatecall (=> 1 byte),
     *                     to as a address (=> 20 bytes),
     *                     value as a uint256 (=> 32 bytes),
     *                     data length as a uint256 (=> 32 bytes),
     *                     data as bytes.
     *                     see abi.encodePacked for more information on packed encoding
     * @notice This method is payable as delegatecalls keep the msg.value from the previous call
     *         If the calling method (e.g. execTransaction) received ETH this would revert otherwise
     */
    function execute(bytes memory transactions) external notPaused nonReentrant {
        uint256 transactionsLength = transactions.length;

        /// @notice min transaction length is 85 bytes (a single function selector with no calldata)
        if (transactionsLength < 85) revert InvalidTransactionLength();

        // the caller is the operator
        address operator = msg.sender;

        // lets iterate over the transactions. Each transaction will be verified and then executed through the safe.
        for (uint256 i = 0; i < transactionsLength;) {
            address target;
            bytes4 targetSelector;
            uint256 value;
            uint8 operation;
            uint256 dataLength;
            bytes memory data;
            uint256 cursor = i;

            assembly {
                // offset 32 bytes to skip the length of the transactions array
                cursor := add(cursor, 0x20)

                // First byte of the data is the operation.
                // We shift by 248 bits (256 - 8 [operation byte]) it right since mload will always load 32 bytes (a word).
                // This will also zero out unused data.
                cursor := add(transactions, cursor)
                operation := shr(0xf8, mload(cursor))

                // We offset the cursor by 1 byte (operation byte)
                // We shift it right by 96 bits (256 - 160 [20 address bytes]) to right-align the data and zero out unused data.
                cursor := add(cursor, 0x01)
                target := shr(0x60, mload(cursor))

                // We offset the cursor by 21 byte (operation byte + 20 address bytes)
                cursor := add(cursor, 0x14)
                value := mload(cursor)

                // We offset the cursor by another 32 bytes to read the data length
                cursor := add(cursor, 0x20)
                dataLength := mload(cursor)

                data := cursor
                targetSelector :=
                    and(
                        // we skip the first 32 bytes (length of the data array)
                        mload(add(data, 0x20)),
                        /// bitmask to get the first 4 bytes (the selector)
                        0xFFFFFFFF00000000000000000000000000000000000000000000000000000000
                    )
            }

            bytes32 hookPointer = HookLib.hookPointer(operator, target, operation, targetSelector);
            Hooks memory hook = hooks[hookPointer];

            if (!hook.defined) {
                revert UndefinedHooks();
            }

            if (hook.beforeTrxHook != address(0)) {
                IBeforeTransaction(hook.beforeTrxHook).checkBeforeTransaction(
                    fund, target, targetSelector, operation, value, data
                );
            }

            (bool success, bytes memory returnData) = ISafe(fund)
                .execTransactionFromModuleReturnData(
                target,
                value,
                data,
                operation == uint8(Enum.Operation.DelegateCall)
                    ? Enum.Operation.DelegateCall
                    : Enum.Operation.Call
            );

            if (!success) {
                // Decode the return data to get the error message
                if (returnData.length > 0) {
                    string memory errorMessage;

                    assembly {
                        // skip: 1 word (length of the return data)
                        // skip: 4 bytes (error message signature)
                        // skip: 1 word (length of the error message)
                        // total skipped: 0x44 bytes
                        errorMessage := add(returnData, 0x44)
                    }

                    revert TransactionExecutionFailed(errorMessage);
                } else {
                    revert TransactionExecutionFailed("No error provided");
                }
            }

            if (hook.afterTrxHook != address(0)) {
                IAfterTransaction(hook.afterTrxHook).checkAfterTransaction(
                    fund, target, targetSelector, operation, value, data, returnData
                );
            }

            unchecked {
                /// @dev the next entry starts at 85 byte + data length.
                i += 0x55 + dataLength;
            }
        }
    }

    function pause() external onlyFund {
        paused = true;

        emit Paused();
    }

    function unpause() external onlyFund {
        paused = false;

        emit Unpaused();
    }
}
