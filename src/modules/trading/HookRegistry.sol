// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@src/interfaces/IHookRegistry.sol";
import {HookLib} from "./Hooks.sol";
import {HookConfig, Hooks} from "./Structs.sol";
import "./Errors.sol";
import "./Events.sol";

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

        hooks[pointer] = Hooks({
            beforeTrxHook: config.beforeTrxHook,
            afterTrxHook: config.afterTrxHook,
            defined: true // TODO: change to status code, same cost but more descriptive
        });

        emit HookSet(
            config.operator,
            config.target,
            config.operation,
            config.targetSelector,
            config.beforeTrxHook,
            config.afterTrxHook
        );
    }

    function removeHooks(HookConfig calldata config) external onlyFund {
        delete hooks[config.pointer()];

        emit HookRemoved(config.operator, config.target, config.operation, config.targetSelector);
    }
}
