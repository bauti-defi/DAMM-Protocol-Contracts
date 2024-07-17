// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Hooks, HookConfig} from "@src/modules/trading/Hooks.sol";

interface IHookRegistry {
    function fund() external returns (address);

    function getHooks(address operator, address target, uint8 operation, bytes4 selector)
        external
        view
        returns (Hooks memory);
    function setHooks(HookConfig calldata config) external;
    function removeHooks(HookConfig calldata config) external;
}
