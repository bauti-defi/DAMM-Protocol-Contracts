// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IProtocolState} from "@src/interfaces/IProtocolState.sol";

abstract contract ProtocolStateAccesor is IProtocolState {
    IProtocolState public immutable protocolState;

    constructor(address _protocolState) {
        protocolState = IProtocolState(_protocolState);
    }

    modifier notPaused() {
        require(!protocolState.paused(), "Pausable: paused");
        _;
    }

    modifier isPaused() {
        require(protocolState.paused(), "Pausable: not paused");
        _;
    }

    function paused() public view returns (bool) {
        return protocolState.paused();
    }

    function owner() public view returns (address) {
        return protocolState.owner();
    }

    function ownershipHandoverExpiresAt(address pendingOwner) public view returns (uint256) {
        return protocolState.ownershipHandoverExpiresAt(pendingOwner);
    }
}
