// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

/// @notice Represents an EVM transaction to be executed through the Safe
/// @dev Function selector is separated from data to allow for efficient hook routing
struct Transaction {
    /// @notice Amount of ETH to send with the transaction
    uint256 value;
    /// @notice Target contract address to call
    address target;
    /// @notice Transaction type: 0 for call, 1 for delegatecall
    uint8 operation;
    /// @notice Function selector to call on the target
    /// @dev Packed with data field to form complete function call: abi.encodePacked(targetSelector, data)
    bytes4 targetSelector;
    /// @notice Calldata for the function (excluding selector)
    bytes data;
}

/// @notice Defines before/after hooks for a specific transaction route
/// @dev A route is uniquely identified by (operator, target, operation, selector)
struct Hooks {
    /// @notice Address of hook to call before transaction execution
    /// @dev Can be address(0) to skip before-hook execution
    address beforeTrxHook;
    /// @notice Address of hook to call after transaction execution
    /// @dev Can be address(0) to skip after-hook execution
    address afterTrxHook;
    /// @notice Whether this hook configuration has been defined
    /// @dev Must be true for transaction execution to proceed
    bool defined;
}

/// @notice Parameters for registering a new transaction route hook
/// @dev Used to configure which hooks should execute for a specific transaction route
struct HookConfig {
    /// @notice Address allowed to execute this transaction route
    address operator;
    /// @notice Target contract address for the transaction
    address target;
    /// @notice Hook to call before transaction execution
    address beforeTrxHook;
    /// @notice Hook to call after transaction execution
    address afterTrxHook;
    /// @notice Transaction type: 0 for call, 1 for delegatecall
    uint8 operation;
    /// @notice Function selector that identifies this route
    bytes4 targetSelector;
}
