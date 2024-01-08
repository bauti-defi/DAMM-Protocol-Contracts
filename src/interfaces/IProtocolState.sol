// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IPausable} from "@src/interfaces/libs/IPausable.sol";

interface IProtocolState is IPausable {
    function requireNotStopped() external view;
}
