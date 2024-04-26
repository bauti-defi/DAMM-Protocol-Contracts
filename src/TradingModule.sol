// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {ISafe} from "@src/interfaces/ISafe.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {ITradingModule} from "@src/interfaces/ITradingModule.sol";
import {IBeforeTransaction, IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";
import "@src/interfaces/IHookRegistry.sol";

contract TradingModule is ITradingModule, ReentrancyGuard {
    address public immutable fund;
    IHookRegistry public immutable hookRegistry;
    uint256 public maxGasPriorityInBasisPoints;
    bool public paused;

    modifier onlyFund() {
        require(msg.sender == fund, "only fund");
        _;
    }

    modifier notPaused() {
        require(paused == false, "paused");
        _;
    }

    // TODO: calculate the gas overhead of the refunding logic so we can refund the correct amount of gas
    // will never be able to refund 100% but we can get close
    modifier refundGasToCaller() {
        uint256 gasAtStart = gasleft();

        // failsafe for caller not to be able to set a gas price that is too high
        // the fund can update this limit in moments of emergency (e.g. high gas prices, network congestion, etc.)
        // gasPriority = tx.gasprice - block.basefee
        if (
            maxGasPriorityInBasisPoints > 0 && tx.gasprice > block.basefee
                && ((tx.gasprice - block.basefee) * 10000) / tx.gasprice >= maxGasPriorityInBasisPoints
        ) {
            revert GasLimitExceeded();
        }

        _;

        require(
            ISafe(fund).execTransactionFromModule(
                msg.sender, (gasAtStart - gasleft()) * tx.gasprice, "", Enum.Operation.Call
            ),
            "gas refund failed"
        );
    }

    constructor(address owner, address _hookRegistry) {
        fund = owner;
        hookRegistry = IHookRegistry(_hookRegistry);
        maxGasPriorityInBasisPoints = 500; // 5% as default
    }

    function setMaxGasPriorityInBasisPoints(uint256 newMaxGasPriorityInBasisPoints)
        external
        onlyFund
    {
        maxGasPriorityInBasisPoints = newMaxGasPriorityInBasisPoints;
    }

    function _executeAndReturnDataOrRevert(
        address target,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnData) =
            ISafe(fund).execTransactionFromModuleReturnData(target, value, data, operation);

        if (!success) {
            assembly {
                // bubble up revert reason if length > 0
                if gt(mload(returnData), 0) { revert(add(returnData, 0x20), mload(returnData)) }
                // else revert with no reason
                revert(0, 0)
            }
        }

        return returnData;
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
    function execute(bytes memory transactions) external nonReentrant refundGasToCaller notPaused {
        uint256 transactionsLength = transactions.length;

        /// @notice min transaction length is 85 bytes (a single function selector with no calldata)
        if (transactionsLength < 85) revert InvalidTransactionLength();

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

                targetSelector :=
                    and(
                        mload(add(cursor, 0x20)), // skip array length, grab the first word, first 4 bytes is the function selector
                        0xFFFFFFFF00000000000000000000000000000000000000000000000000000000
                    )

                mstore(cursor, sub(dataLength, 0x04)) // now we overwrite the data length to subtract the selector length
                mcopy(add(cursor, 0x20), add(cursor, 0x24), sub(dataLength, 0x04)) // now we copy the data without the selector
                data := cursor
            }

            // msg.sender is operator
            Hooks memory hook = hookRegistry.getHooks(msg.sender, target, operation, targetSelector);

            if (!hook.defined) {
                revert UndefinedHooks();
            }

            if (hook.beforeTrxHook != address(0)) {
                _executeAndReturnDataOrRevert(
                    hook.beforeTrxHook, // target
                    0, // value
                    abi.encodeWithSelector(
                        IBeforeTransaction.checkBeforeTransaction.selector,
                        target,
                        targetSelector,
                        operation,
                        value,
                        data
                    ), // data
                    Enum.Operation.Call // operation
                );
            }

            bytes memory returnData = _executeAndReturnDataOrRevert(
                target,
                value,
                abi.encodePacked(targetSelector, data),
                operation == uint8(Enum.Operation.DelegateCall)
                    ? Enum.Operation.DelegateCall
                    : Enum.Operation.Call
            );

            if (hook.afterTrxHook != address(0)) {
                _executeAndReturnDataOrRevert(
                    hook.afterTrxHook,
                    0,
                    abi.encodeWithSelector(
                        IAfterTransaction.checkAfterTransaction.selector,
                        target,
                        targetSelector,
                        operation,
                        value,
                        data,
                        returnData
                    ),
                    Enum.Operation.Call
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
