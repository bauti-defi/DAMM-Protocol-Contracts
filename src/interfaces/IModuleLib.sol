// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// @title IModuleLib
/// @notice Interface for deploying and managing fund modules
interface IModuleLib {
    /// @notice Emitted when a new module is deployed
    /// @param safe Address of the fund that deployed the module
    /// @param module Address of the newly deployed module
    /// @param value Amount of ETH sent during deployment
    event ModuleDeployed(address safe, address module, uint256 value);

    /// @notice Deploys a new module using CREATE2 and enables it on the fund
    /// @param salt Unique salt for deterministic deployment
    /// @param value Amount of ETH to send during deployment
    /// @param creationCode Contract creation bytecode
    /// @return module Address of the deployed module
    function deployModule(bytes32 salt, uint256 value, bytes memory creationCode)
        external
        returns (address module);

    /// @notice Enables an existing module on the fund
    /// @param module Address of the module to enable
    function addModule(address module) external;
}
