// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {IBeforeTransaction, IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";

contract AaveV3Hooks is IBeforeTransaction, IAfterTransaction {

    function checkBeforeTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256 value,
        bytes memory data
    ) external override {
        // do something
    }

    function checkAfterTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256 value,
        bytes memory data,
        bytes memory returnData) external override {
        // TODO: do something
    }

}