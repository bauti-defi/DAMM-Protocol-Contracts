// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IPausableActions {
    function pause() external;

    function unpause() external;
}
