// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import "@src/lib/ProtocolStateAccesor.sol";
import {IPausableState} from "@src/interfaces/libs/IPausableState.sol";

abstract contract BasePausable is IPausableState {
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
