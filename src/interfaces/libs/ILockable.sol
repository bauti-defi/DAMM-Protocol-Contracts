// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

interface ILockable {
    function lock() external;

    function unlock() external;

    function locked() external view returns (bool);

    function locker() external view returns (address);
}
