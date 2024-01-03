// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {IProtocolState} from "@src/interfaces/IProtocolState.sol";

library ProtocolStateAccesor {
    function paused(IProtocolState protocolState) internal view returns (bool) {
        return protocolState.paused();
    }

    function owner(IProtocolState protocolState) internal view returns (address) {
        return protocolState.owner();
    }

    function ownershipHandoverExpiresAt(IProtocolState protocolState, address pendingOwner)
        internal
        view
        returns (uint256)
    {
        return protocolState.ownershipHandoverExpiresAt(pendingOwner);
    }
}
