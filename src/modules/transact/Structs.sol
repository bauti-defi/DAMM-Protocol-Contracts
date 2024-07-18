// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

struct Transaction {
    uint256 value;
    address target;
    uint8 operation;
    bytes4 targetSelector;
    bytes data;
}

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
