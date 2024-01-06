// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {IProtocolAccessController} from "@src/interfaces/IProtocolAccessController.sol";

contract ProtocolAccessController is OwnableRoles, IProtocolAccessController {
    /// @notice The role which allows pausing the protocol incase of emergency
    uint256 public constant PAUSER_ROLE = _ROLE_0;

    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    function isOwnerOrPauser(address _address) external view override returns (bool) {
        return owner() == _address || hasAnyRole(_address, PAUSER_ROLE);
    }

    function isOwner(address _address) external view override returns (bool) {
        return owner() == _address;
    }

    function setPauser(address _pauser) external override onlyOwner {
        _setRoles(_pauser, PAUSER_ROLE);
    }

    function removePauser(address _pauser) external override onlyOwner {
        _removeRoles(_pauser, PAUSER_ROLE);
    }
}
