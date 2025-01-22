// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "@openzeppelin-contracts/utils/introspection/ERC165Checker.sol";
import {IBeforeTransaction, IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import "@src/libs/Errors.sol";
import "./Structs.sol";

/// @title Hook Library
/// @notice Helper functions for validating and managing transaction hooks
/// @dev Used by HookRegistry to validate hook configurations and generate unique identifiers
library HookLib {
    using ERC165Checker for address;

    /// @notice Generates a unique identifier for a hook configuration
    /// @param config The hook configuration to generate a pointer for
    /// @return The unique identifier as bytes32
    function pointer(HookConfig memory config) internal pure returns (bytes32) {
        return hookPointer(config.operator, config.target, config.operation, config.targetSelector);
    }

    /// @notice Validates a hook configuration
    /// @dev Checks operator, target, hooks, and operation validity
    /// @param config The hook configuration to validate
    /// @param fund The fund contract address
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

    /// @notice Generates a unique identifier for hook route parameters
    /// @dev Encodes parameters into a bytes32 identifier using keccak256
    /// @param operator The address allowed to execute this route
    /// @param target The target contract address
    /// @param operation The transaction type (0=call, 1=delegatecall)
    /// @param selector The function selector for this route
    /// @return The unique identifier as bytes32
    function hookPointer(address operator, address target, uint8 operation, bytes4 selector)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(operator, target, operation, selector));
    }
}
