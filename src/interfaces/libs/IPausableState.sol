// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IPausableState {
    function paused() external view returns (bool);
}
