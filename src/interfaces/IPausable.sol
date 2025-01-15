// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

interface IPausable {
    function paused() external returns (bool);
}
