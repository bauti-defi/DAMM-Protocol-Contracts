// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "@src/interfaces/IHookRegistry.sol";
import "@src/libs/Errors.sol";
import {HookLib} from "./Hooks.sol";
import {HookConfig, Hooks} from "./Structs.sol";

contract HookRegistry is IHookRegistry {
    using HookLib for HookConfig;

    address public immutable override fund;

    /// keccak256(abi.encode(operator, target, operation, selector)) => hooks
    /// bytes20 + bytes20 + bytes8 + bytes4 = 52 bytes
    mapping(bytes32 hookPointer => Hooks) private hooks;

    modifier onlyFund() {
        if (msg.sender != fund) {
            revert Errors.OnlyFund();
        }
        _;
    }

    constructor(address _fund) {
        fund = _fund;
    }

    function getHooks(address operator, address target, uint8 operation, bytes4 selector)
        external
        view
        returns (Hooks memory)
    {
        return hooks[HookLib.hookPointer(operator, target, operation, selector)];
    }

    function setHooks(HookConfig calldata config) external onlyFund {
        config.checkConfigIsValid(fund);

        bytes32 pointer = config.pointer();

        /// TODO: test this
        if (hooks[pointer].defined) {
            revert Errors.Hook_AlreadyDefined();
        }

        hooks[pointer] = Hooks({
            beforeTrxHook: config.beforeTrxHook,
            afterTrxHook: config.afterTrxHook,
            defined: true
        });

        emit HookSet(
            pointer,
            config.operator,
            config.target,
            config.operation,
            config.targetSelector,
            config.beforeTrxHook,
            config.afterTrxHook
        );
    }

    function removeHooks(HookConfig calldata config) external onlyFund {
        bytes32 pointer = config.pointer();

        if (!hooks[pointer].defined) {
            revert Errors.Hook_NotDefined();
        }

        delete hooks[pointer];

        emit HookRemoved(pointer);
    }
}
