// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Enum} from "@safe-contracts/common/Enum.sol";

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

library HookLib {
    function pointer(HookConfig memory config) internal pure returns (bytes32) {
        return hookPointer(config.operator, config.target, config.operation, config.targetSelector);
    }

    function checkConfigIsValid(HookConfig memory config, address fund) internal view {
        require(config.operator != address(0), "operator is zero address");
        require(config.operator != fund, "operator is fund");
        require(config.operator != address(this), "operator is self");

        require(config.target != address(0), "target is zero address");
        require(config.target != address(this), "target is self");

        require(config.beforeTrxHook != address(this), "beforeTrxHook is self");
        require(config.beforeTrxHook != config.operator, "beforeTrxHook is operator");

        require(config.afterTrxHook != address(this), "afterTrxHook is self");
        require(config.afterTrxHook != config.operator, "afterTrxHook is operator");

        require(config.targetSelector != bytes4(0), "target selector is zero");
        // only 0 or 1 allowed (0 = call, 1 = delegatecall)
        require(
            config.operation == uint8(Enum.Operation.Call)
                || config.operation == uint8(Enum.Operation.DelegateCall),
            "operation is invalid"
        );
    }

    function hookPointer(address operator, address target, uint8 operation, bytes4 selector)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(operator, target, operation, selector));
    }
}

event HookSet(bytes32 pointer);

event HookRemoved(address operator, address target, uint8 operation, bytes4 selector);

event Paused();

event Unpaused();

contract HookRegistry {
    using HookLib for HookConfig;

    address public immutable fund;

    bool public paused;

    // keccak256(abi.encode(operator, target, operation, selector)) => hooks
    // bytes20 + bytes20 + bytes8 + bytes4 = 52 bytes
    mapping(bytes32 hookPointer => Hooks) private hooks;

    modifier onlyFund() {
        require(msg.sender == fund, "only fund");
        _;
    }

    modifier notPaused() {
        require(paused == false, "paused");
        _;
    }

    constructor(address owner) {
        fund = owner;
    }

    function _setHooks(HookConfig calldata config) internal notPaused {
        config.checkConfigIsValid(fund);

        bytes32 pointer = config.pointer();

        hooks[pointer] = Hooks({
            beforeTrxHook: config.beforeTrxHook,
            afterTrxHook: config.afterTrxHook,
            defined: true
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
