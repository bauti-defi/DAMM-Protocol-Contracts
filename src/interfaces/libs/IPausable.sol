// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IPausable {
    function paused() external view returns (bool);

    function requireNotStopped() external view;

    function pause() external;

    function unpause() external;
}
