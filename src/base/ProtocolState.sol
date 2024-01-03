// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IProtocolState} from "@src/interfaces/IProtocolState.sol";
import {IProtocolStateActions} from "@src/interfaces/IProtocolStateActions.sol";
import {Ownable} from "@solady/auth/Ownable.sol";

contract ProtocolState is Ownable, IProtocolState, IProtocolStateActions {
    event Paused(address pauser);
    event Unpaused(address unpauser);

    bool public paused;

    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    function owner() public view override(Ownable, IProtocolState) returns (address) {
        return super.owner();
    }

    function pause() public onlyOwner {
        paused = true;

        emit Paused(msg.sender);
    }

    function unpause() public onlyOwner {
        paused = false;

        emit Unpaused(msg.sender);
    }
}
