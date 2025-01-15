// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {Errors} from "@src/libs/Errors.sol";
import {IPauser} from "@src/interfaces/IPauser.sol";
import {IPausable} from "@src/interfaces/IPausable.sol";

abstract contract Pausable is IPausable {
    address private immutable pauser;

    constructor(address pauser_) {
        pauser = pauser_;
    }

    modifier notPaused() {
        if (isPaused()) revert Errors.Paused();
        _;
    }

    function isPaused() internal returns (bool) {
        return IPauser(pauser).paused(address(this));
    }

    function paused() external override returns (bool) {
        return isPaused();
    }
}
