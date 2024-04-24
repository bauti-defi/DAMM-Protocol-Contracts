// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IBeforeTransaction {
    function checkBeforeTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256 value,
        bytes memory data
    ) external;
}

interface IAfterTransaction {
    function checkAfterTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256 value,
        bytes memory data,
        bytes memory returnData
    ) external;
}
