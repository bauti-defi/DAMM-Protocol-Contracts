// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IPausableActions {
    function pause() external;

    function unpause() external;
}
