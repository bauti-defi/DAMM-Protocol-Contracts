// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {IHookRegistry} from "@src/interfaces/IHookRegistry.sol";
import {HookLib, HookConfig, Hooks} from "@src/lib/Hooks.sol";

contract HookRegistry is IHookRegistry {
    using HookLib for HookConfig;

    address public immutable override fund;

    // keccak256(abi.encode(operator, target, operation, selector)) => hooks
    // bytes20 + bytes20 + bytes8 + bytes4 = 52 bytes
    mapping(bytes32 hookPointer => Hooks) private hooks;

    modifier onlyFund() {
        require(msg.sender == fund, "only fund");
        _;
    }

    constructor(address _fund) {
        fund = _fund;
    }

    function _setHooks(HookConfig calldata config) internal {
        config.checkConfigIsValid(fund);

        bytes32 pointer = config.pointer();

        hooks[pointer] = Hooks({
            beforeTrxHook: config.beforeTrxHook,
            afterTrxHook: config.afterTrxHook,
            defined: true // TODO: change to status code, same cost but more descriptive
        });

        emit HookSet(pointer);
    }

    function batchSetHooks(HookConfig[] calldata configs) external onlyFund {
        uint256 length = configs.length;
        for (uint256 i = 0; i < length;) {
            _setHooks(configs[i]);

            unchecked {
                ++i;
            }
        }
    }

    function getHooks(address operator, address target, uint8 operation, bytes4 selector)
        external
        view
        returns (Hooks memory)
    {
        return hooks[HookLib.hookPointer(operator, target, operation, selector)];
    }

    function setHooks(HookConfig calldata config) external onlyFund {
        _setHooks(config);
    }

    function _removeHooks(address operator, address target, uint8 operation, bytes4 selector)
        internal
    {
        delete hooks[HookLib.hookPointer(operator, target, operation, selector)];

        emit HookRemoved(operator, target, operation, selector);
    }

    function batchRemoveHooks(HookConfig[] calldata configs) external onlyFund {
        uint256 length = configs.length;
        for (uint256 i = 0; i < length;) {
            _removeHooks(
                configs[i].operator,
                configs[i].target,
                configs[i].operation,
                configs[i].targetSelector
            );

            unchecked {
                ++i;
            }
        }
    }

    function removeHooks(HookConfig calldata config) external onlyFund {
        _removeHooks(config.operator, config.target, config.operation, config.targetSelector);
    }
}
