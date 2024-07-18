// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Hooks, HookConfig} from "@src/modules/transact/Hooks.sol";

interface IHookRegistry {
    error Hook_InvalidOperator();
    error Hook_InvalidTargetAddress();
    error Hook_InvalidBeforeHookAddress();
    error Hook_InvalidAfterHookAddress();
    error Hook_InvalidOperation();
    error OnlyFund();

    event HookSet(
        address operator,
        address target,
        uint8 operation,
        bytes4 selector,
        address beforeHook,
        address afterHook
    );

    event HookRemoved(address operator, address target, uint8 operation, bytes4 selector);

    function fund() external returns (address);

    function getHooks(address operator, address target, uint8 operation, bytes4 selector)
        external
        view
        returns (Hooks memory);
    function setHooks(HookConfig calldata config) external;
    function removeHooks(HookConfig calldata config) external;
}
