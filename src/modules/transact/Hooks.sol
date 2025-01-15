// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "@openzeppelin-contracts/utils/introspection/ERC165Checker.sol";
import {IBeforeTransaction, IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import "@src/libs/Errors.sol";
import "./Structs.sol";

library HookLib {
    using ERC165Checker for address;

    function pointer(HookConfig memory config) internal pure returns (bytes32) {
        return hookPointer(config.operator, config.target, config.operation, config.targetSelector);
    }

    function checkConfigIsValid(HookConfig memory config, address fund) internal view {
        /// basic operator sanity checks
        if (
            config.operator == address(0) || config.operator == fund
                || config.operator == address(this)
        ) {
            revert Errors.Hook_InvalidOperator();
        }

        /// basic target sanity checks
        if (config.target == address(0)) {
            revert Errors.Hook_InvalidTargetAddress();
        }

        /// basic beforeTrxHook sanity checks
        if (
            config.beforeTrxHook != address(0)
                && !config.beforeTrxHook.supportsInterface(type(IBeforeTransaction).interfaceId)
        ) {
            revert Errors.Hook_InvalidBeforeHook();
        }

        /// basic afterTrxHook sanity checks
        if (
            config.afterTrxHook != address(0)
                && !config.afterTrxHook.supportsInterface(type(IAfterTransaction).interfaceId)
        ) {
            revert Errors.Hook_InvalidAfterHook();
        }

        // only 0 or 1 allowed (0 = call, 1 = delegatecall)
        if (config.operation != 0 && config.operation != 1) {
            revert Errors.Hook_InvalidOperation();
        }
    }

    function hookPointer(address operator, address target, uint8 operation, bytes4 selector)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(operator, target, operation, selector));
    }
}
