// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// @title IModuleLib
/// @notice Interface for deploying and managing fund modules
interface IModuleLib {
    /// @notice Emitted when a new module is deployed
    /// @param safe Address of the fund that deployed the module
    /// @param module Address of the newly deployed module
    /// @param value Amount of ETH sent during deployment
    /// @param roles Bitmap of roles granted to the module
    event ModuleDeployed(address safe, address module, uint256 value, uint256 roles);

    /// @notice Deploys a new module using CREATE2 and enables it on the fund
    /// @param salt Unique salt for deterministic deployment
    /// @param value Amount of ETH to send during deployment
    /// @param creationCode Contract creation bytecode
    /// @return module Address of the deployed module
    function deployModule(bytes32 salt, uint256 value, bytes memory creationCode)
        external
        returns (address module);

    /// @notice Deploys a new module and grants it roles
    /// @param salt Unique salt for deterministic deployment
    /// @param value Amount of ETH to send during deployment
    /// @param creationCode Contract creation bytecode
    /// @param roles Bitmap of roles to grant to the module
    /// @return module Address of the deployed module
    function deployModuleWithRoles(
        bytes32 salt,
        uint256 value,
        bytes memory creationCode,
        uint256 roles
    ) external returns (address module);

    /// @notice Enables an existing module on the fund
    /// @param module Address of the module to enable
    function addModule(address module) external;

    /// @notice Enables an existing module and grants it roles
    /// @param module Address of the module to enable
    /// @param roles Bitmap of roles to grant to the module
    function addModuleWithRoles(address module, uint256 roles) external;
}
