// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IModuleLib {
    event ModuleDeployed(address safe, address module, uint256 value, uint256 roles);

    function deployModule(bytes32 salt, uint256 value, bytes memory creationCode)
        external
        returns (address module);

    function deployModuleWithRoles(
        bytes32 salt,
        uint256 value,
        bytes memory creationCode,
        uint256 roles
    ) external returns (address module);

    function addModule(address module) external;

    function addModuleWithRoles(address module, uint256 roles) external;
}
