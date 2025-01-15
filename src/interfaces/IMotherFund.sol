// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

/// @title IMotherFund
/// @notice Interface for managing parent-child fund relationships and hierarchical fund structures
interface IMotherFund {
    /// @notice Gets all child funds managed by this fund
    /// @return Array of child fund addresses
    function getChildFunds() external view returns (address[] memory);

    /// @notice Adds a new child fund to this fund's management
    /// @param childFund Address of the child fund to add
    /// @return False if fund was already a child, true if successfully added
    function addChildFund(address childFund) external returns (bool);

    /// @notice Removes a child fund from this fund's management
    /// @param childFund Address of the child fund to remove
    /// @return False if fund wasn't a child, true if successfully removed
    function removeChildFund(address childFund) external returns (bool);

    /// @notice Checks if a fund is managed as a child of this fund
    /// @param childFund Address of the fund to check
    /// @return True if the address is a child fund
    function isChildFund(address childFund) external view returns (bool);
}
