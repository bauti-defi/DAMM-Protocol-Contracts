// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Hooks, HookConfig} from "@src/modules/transact/Hooks.sol";

interface IHookRegistry {
    /// @notice Emitted when a new hook configuration is set
    /// @param pointer Unique identifier for this hook configuration
    /// @param operator Address allowed to execute this route
    /// @param target Target contract address
    /// @param operation Transaction type (0=call, 1=delegatecall)
    /// @param selector Function selector for this route
    /// @param beforeHook Address of hook to call before execution
    /// @param afterHook Address of hook to call after execution
    event HookSet(
        bytes32 pointer,
        address operator,
        address target,
        uint8 operation,
        bytes4 selector,
        address beforeHook,
        address afterHook
    );

    /// @notice Emitted when a hook configuration is removed
    /// @param pointer Unique identifier of the removed hook configuration
    event HookRemoved(bytes32 pointer);

    /// @notice The fund contract address
    function fund() external returns (address);

    /// @notice Gets the hooks for a specific transaction route
    /// @param operator The address allowed to execute the transaction
    /// @param target The target contract address
    /// @param operation The transaction type (0=call, 1=delegatecall)
    /// @param selector The function selector
    /// @return The hook configuration for this route
    function getHooks(address operator, address target, uint8 operation, bytes4 selector)
        external
        view
        returns (Hooks memory);

    /// @notice Registers a new hook configuration for a transaction route
    /// @dev Only callable by fund contract
    /// @param config The hook configuration to register
    function setHooks(HookConfig calldata config) external;

    /// @notice Removes a hook configuration for a transaction route
    /// @dev Only callable by fund contract
    /// @param config The hook configuration to remove
    function removeHooks(HookConfig calldata config) external;
}
