// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@src/libs/Errors.sol";
import "./Structs.sol";

// cast sig "isOwner(address)"
bytes4 constant IS_OWNER_SAFE_SELECTOR = 0x2f54bf6e;

library HookLib {
    function pointer(HookConfig memory config) internal pure returns (bytes32) {
        return hookPointer(config.operator, config.target, config.operation, config.targetSelector);
    }

    function checkConfigIsValid(HookConfig memory config, address fund) internal view {
        /// basic operator sanity checks
        if (
            config.operator == address(0) || config.operator == fund
                || config.operator == address(this)
        ) {
            revert Errors.Hook_InvalidOperator();
        }

        (bool success, bytes memory returnData) =
            fund.staticcall(abi.encodeWithSelector(IS_OWNER_SAFE_SELECTOR, config.operator));

        /// @notice fund admin cannot be an operator
        if (!success || abi.decode(returnData, (bool))) {
            revert Errors.Hook_InvalidOperator();
        }

        /// basic target sanity checks
        if (config.target == address(0) || config.target == address(this)) {
            revert Errors.Hook_InvalidTargetAddress();
        }

        /// basic beforeTrxHook sanity checks
        if (config.beforeTrxHook == address(this) || config.beforeTrxHook == config.operator) {
            revert Errors.Hook_InvalidBeforeHookAddress();
        }

        /// basic afterTrxHook sanity checks
        if (config.afterTrxHook == address(this) || config.afterTrxHook == config.operator) {
            revert Errors.Hook_InvalidAfterHookAddress();
        }

        // only 0 or 1 allowed (0 = call, 1 = delegatecall)
        if (config.operation != 0 && config.operation != 1) {
            revert Errors.Hook_InvalidOperation();
        }
    }

    function hookPointer(address operator, address target, uint8 operation, bytes4 selector)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(operator, target, operation, selector));
    }
}
