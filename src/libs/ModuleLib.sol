// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {IModuleLib} from "@src/interfaces/IModuleLib.sol";
import {IFund} from "@src/interfaces/IFund.sol";
import "@src/libs/Errors.sol";
import {NULL_ROLE} from "@src/libs/Constants.sol";

/// @title ModuleLib
/// @notice Implementation of module deployment and management for funds
/// @dev Uses CREATE2 for deterministic deployments and handles module initialization
contract ModuleLib is IModuleLib {
    /// @notice Address of this contract, used for delegatecall checks
    address private immutable self;

    constructor() {
        self = address(this);
    }

    /// @notice Ensures function is called via delegatecall
    modifier isDelegateCall() {
        if (address(this) == self) revert Errors.OnlyDelegateCall();
        _;
    }

    /// @notice Internal function to deploy and enable a module
    /// @dev The safe must delegate call this contract for the module to be added properly
    /// @param salt Unique salt for deterministic deployment
    /// @param value Amount of ETH to send during deployment
    /// @param creationCode Contract creation bytecode
    /// @return module Address of the deployed module
    function _deployModule(bytes32 salt, uint256 value, bytes memory creationCode)
        internal
        returns (address module)
    {
        if (address(this).balance < value) revert Errors.ModuleLib_InsufficientBalance();
        if (creationCode.length == 0) revert Errors.ModuleLib_EmptyBytecode();

        // solhint-disable-next-line no-inline-assembly
        assembly {
            module := create2(value, add(0x20, creationCode), mload(creationCode), salt)
        }
        if (module == address(0)) revert Errors.ModuleLib_DeploymentFailed();

        IFund(address(this)).enableModule(module);
        if (!IFund(address(this)).isModuleEnabled(module)) {
            revert Errors.ModuleLib_ModuleSetupFailed();
        }
    }

    /// @inheritdoc IModuleLib
    function deployModule(bytes32 salt, uint256 value, bytes memory creationCode)
        external
        isDelegateCall
        returns (address module)
    {
        module = _deployModule(salt, value, creationCode);
        emit ModuleDeployed(address(this), module, value, NULL_ROLE);
    }

    /// @inheritdoc IModuleLib
    function deployModuleWithRoles(
        bytes32 salt,
        uint256 value,
        bytes memory creationCode,
        uint256 roles
    ) external isDelegateCall returns (address module) {
        module = _deployModule(salt, value, creationCode);
        IFund(address(this)).grantRoles(module, roles);
        emit ModuleDeployed(address(this), module, value, roles);
    }

    /// @inheritdoc IModuleLib
    function addModule(address module) external isDelegateCall {
        IFund(address(this)).enableModule(module);
    }

    /// @inheritdoc IModuleLib
    function addModuleWithRoles(address module, uint256 roles) external isDelegateCall {
        IFund(address(this)).enableModule(module);
        IFund(address(this)).grantRoles(module, roles);
    }
}
