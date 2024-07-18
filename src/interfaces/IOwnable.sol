// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IOwnable {
    event RolesGranted(address indexed module, uint256 roles);

    function grantRoles(address account, uint256 roles) external;
    function hasAllRoles(address account, uint256 roles) external view returns (bool);
}
