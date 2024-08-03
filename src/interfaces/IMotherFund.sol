// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMotherFund {
    function getChildFunds() external view returns (address[] memory);
    function addChildFund(address childFund) external returns (bool);
    function removeChildFund(address childFund) external returns (bool);
    function isChildFund(address childFund) external view returns (bool);
}
