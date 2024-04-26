// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

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

// cast sig "isOwner(address)"
bytes4 constant IS_OWNER_SAFE_SELECTOR = 0x2f54bf6e;

library HookLib {
    function pointer(HookConfig memory config) internal pure returns (bytes32) {
        return hookPointer(config.operator, config.target, config.operation, config.targetSelector);
    }

    function checkConfigIsValid(HookConfig memory config, address fund) internal view {
        require(config.operator != address(0), "operator is zero address");
        require(config.operator != fund, "operator is fund");
        require(config.operator != address(this), "operator is self");

        (bool success, bytes memory returnData) =
            fund.staticcall(abi.encodeWithSelector(IS_OWNER_SAFE_SELECTOR, config.operator));
        require(success && !abi.decode(returnData, (bool)), "operator is admin");

        require(config.target != address(0), "target is zero address");
        require(config.target != address(this), "target is self");

        require(config.beforeTrxHook != address(this), "beforeTrxHook is self");
        require(config.beforeTrxHook != config.operator, "beforeTrxHook is operator");

        require(config.afterTrxHook != address(this), "afterTrxHook is self");
        require(config.afterTrxHook != config.operator, "afterTrxHook is operator");

        // only 0 or 1 allowed (0 = call, 1 = delegatecall)
        require(config.operation == 0 || config.operation == 1, "operation is invalid");
    }

    function hookPointer(address operator, address target, uint8 operation, bytes4 selector)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(operator, target, operation, selector));
    }
}
