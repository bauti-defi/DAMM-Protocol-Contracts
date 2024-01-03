// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IProtocolState} from "@src/interfaces/IProtocolState.sol";
import {IProtocolStateActions} from "@src/interfaces/IProtocolStateActions.sol";

contract ProtocolState is IProtocolState, IProtocolStateActions {
    event Paused(address pauser);
    event Unpaused(address unpauser);

    bool public paused;
    address public admin;

    constructor(address _admin) {
        admin = _admin;
    }

    function pause() public {
        require(msg.sender == admin, "Pausable: Only admin can pause");
        paused = true;

        emit Paused(msg.sender);
    }

    function unpause() public {
        require(msg.sender == admin, "Pausable: Only admin can unpause");
        paused = false;

        emit Unpaused(msg.sender);
    }
}
