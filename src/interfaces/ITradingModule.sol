// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface ITradingModule {
    struct Hooks {
        address beforeTrxHook;
        address afterTrxHook;
        bool defined;
    }

    struct HookConfig {
        address operator;
        address target;
        address beforeTrxHook;
        address afterTrxHook;
        uint8 operation;
        bytes4 targetSelector;
    }

    error UndefinedHooks();
    error TransactionExecutionFailed(string returnData);
    error InvalidTransactionLength();

    event HookSet(bytes32 pointer);
    event HookRemoved(address operator, address target, uint8 operation, bytes4 selector);
    event Paused();
    event Unpaused();

    function paused() external returns (bool);
    function fund() external returns (address);

    function getHooks(address operator, address target, uint8 operation, bytes4 selector)
        external
        view
        returns (Hooks memory);
    function setHooks(HookConfig calldata config) external;
    function batchSetHooks(HookConfig[] calldata configs) external;
    function removeHooks(HookConfig calldata config) external;
    function batchRemoveHooks(HookConfig[] calldata configs) external;

    function execute(bytes memory transaction) external;

    function pause() external;
    function unpause() external;
}
