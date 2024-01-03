// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IProtocolState {
    function owner() external view returns (address);
    function paused() external view returns (bool);
}
