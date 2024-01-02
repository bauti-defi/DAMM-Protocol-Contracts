// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

abstract contract Pausable {
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

    modifier notPaused() {
        require(!paused, "Pausable: paused");
        _;
    }

    modifier isPaused() {
        require(paused, "Pausable: not paused");
        _;
    }
}
