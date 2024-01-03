// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Ownable} from "@solady/auth/Ownable.sol";
import {Pausable} from "@openzeppelin-contracts/utils/Pausable.sol";

contract ProtocolState is Ownable, Pausable {
    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
