// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {Pausable} from "@openzeppelin-contracts/utils/Pausable.sol";

contract ProtocolState is OwnableRoles, Pausable {
    uint256 public constant PAUSER_ROLE = _ROLE_0;

    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    function pause() public onlyOwnerOrRoles(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function sweep() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
