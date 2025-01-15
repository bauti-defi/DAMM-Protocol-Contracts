// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

/// @title IOwnable
/// @notice Interface for managing role-based access control in funds
interface IOwnable {
    /// @notice Emitted when roles are granted to a module
    /// @param module Address of the module receiving the roles
    /// @param roles Bitmap of roles granted
    event RolesGranted(address indexed module, uint256 roles);

    /// @notice Assigns roles to a module
    /// @param account Address of the module to grant roles to
    /// @param roles Bitmap of roles to grant
    function grantRoles(address account, uint256 roles) external;

    /// @notice Checks if a module has all specified roles
    /// @param account Address of the module to check
    /// @param roles Bitmap of roles to check for
    /// @return True if module has all specified roles
    function hasAllRoles(address account, uint256 roles) external view returns (bool);
}
