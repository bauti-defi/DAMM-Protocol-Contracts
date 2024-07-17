// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

event Paused();

event Unpaused();

event HookSet(
    address operator,
    address target,
    uint8 operation,
    bytes4 selector,
    address beforeHook,
    address afterHook
);

event HookRemoved(address operator, address target, uint8 operation, bytes4 selector);
