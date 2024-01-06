// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {IProtocolAccessController} from "@src/interfaces/IProtocolAccessController.sol";

contract ProtocolAccessController is OwnableRoles, IProtocolAccessController {
    /// @notice The role which allows pausing the protocol incase of emergency
    uint256 public constant PAUSER_ROLE = _ROLE_0;
    /// @notice The role which allows locking the protocol incase of admin key compromise
    uint256 public constant LOCKER_ROLE = _ROLE_1;

    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    function isOwnerOrPauser(address _address) external view override returns (bool) {
        return owner() == _address || hasAnyRole(_address, PAUSER_ROLE);
    }

    function isOwner(address _address) external view override returns (bool) {
        return owner() == _address;
    }

    function isLocker(address _address) external view returns (bool) {
        return hasAnyRole(_address, LOCKER_ROLE);
    }

    function setLocker(address _locker) external override onlyOwner {
        require(owner() != _locker, "ProtocolAccessController: owner cannot be locker");
        _setRoles(_locker, LOCKER_ROLE);
    }

    function setPauser(address _pauser) external override onlyOwner {
        _setRoles(_pauser, PAUSER_ROLE);
    }

    function removePauser(address _pauser) external override onlyOwner {
        _removeRoles(_pauser, PAUSER_ROLE);
    }

}
