// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import "@src/lib/ProtocolStateAccesor.sol";
import {IPausableState} from "@src/interfaces/libs/IPausableState.sol";

abstract contract Pausable is IPausableState {
    IProtocolState private immutable protocolState;

    constructor(address _protocolState) {
        protocolState = IProtocolState(_protocolState);
    }

    modifier notPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    modifier isPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    function paused() public view returns (bool) {
        return protocolState.paused();
    }
}
