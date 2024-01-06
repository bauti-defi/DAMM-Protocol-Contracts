// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

abstract contract Lockable {
    bool private emergencyLock;
    address private locker;

    constructor() {
        emergencyLock = false;
        locker = address(0);
    }

    function _lock() internal virtual {
        emergencyLock = true;
        locker = msg.sender;
    }

    function _unlock() internal virtual {
        emergencyLock = false;
        locker = address(0);
    }

    function _locked() internal view returns (bool) {
        return emergencyLock;
    }

    function _locker() internal view returns (address) {
        return locker;
    }
}
