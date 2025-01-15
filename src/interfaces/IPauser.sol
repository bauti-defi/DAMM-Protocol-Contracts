// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

interface IPauser {
    event Paused(address target);
    event Unpaused(address target);
    event PausedGlobal();
    event UnpausedGlobal();

    function paused(address caller) external returns (bool);
    function pause(address target) external;
    function unpause(address target) external;
    function pauseGlobal() external;
    function unpauseGlobal() external;
}
