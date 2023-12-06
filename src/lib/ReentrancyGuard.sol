// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

abstract contract ReentrancyGuard {

    error Reentrance();

    enum ReentrancyLock {
        OPEN,
        LOCKED
    }

    // Defaults to OPEN
    ReentrancyLock internal lock;

    modifier nonReentrant() {
        if (lock == ReentrancyLock.LOCKED) {
            revert Reentrance();
        }

        lock = ReentrancyLock.LOCKED;
        _;
        lock = ReentrancyLock.OPEN;
    }
}