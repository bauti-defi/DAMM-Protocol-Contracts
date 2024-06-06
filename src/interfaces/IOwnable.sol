// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IOwnable {
    function grantRoles(address account, uint256 roles) external;
    function hasRoles(address account, uint256 roles) external view returns (bool);
}
