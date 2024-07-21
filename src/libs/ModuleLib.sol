// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IModuleLib} from "@src/interfaces/IModuleLib.sol";
import {IFund} from "@src/interfaces/IFund.sol";
import "@src/libs/Errors.sol";
import {NULL_ROLE} from "@src/libs/Constants.sol";

contract ModuleLib is IModuleLib {
    address private immutable self;

    constructor() {
        self = address(this);
    }

    modifier isDelegateCall() {
        if (address(this) == self) revert Errors.ModuleLib_OnlyDelegateCall();
        _;
    }

    /// deploys a module and adds module to safe.
    /// @dev the safe must delegate call this contract for the module to be added properly
    /// @dev always be cautious when using delegatecall!!
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

        // callback: add module to the safe. msg.sender == because of delegatecall
        IFund(address(this)).enableModule(module);
        if (!IFund(address(this)).isModuleEnabled(module)) {
            revert Errors.ModuleLib_ModuleSetupFailed();
        }
    }

    /// @notice called by the fund
    function deployModule(bytes32 salt, uint256 value, bytes memory creationCode)
        external
        isDelegateCall
        returns (address module)
    {
        module = _deployModule(salt, value, creationCode);

        emit ModuleDeployed(address(this), module, value, NULL_ROLE);
    }

    /// @notice called by the fund
    function deployModuleWithRoles(
        bytes32 salt,
        uint256 value,
        bytes memory creationCode,
        uint256 roles
    ) external isDelegateCall returns (address module) {
        module = _deployModule(salt, value, creationCode);

        // callback: set roles for the module. msg.sender == this because of delegatecall
        IFund(address(this)).grantRoles(module, roles);

        emit ModuleDeployed(address(this), module, value, roles);
    }

    /// @notice called by the fund
    function addModule(address module) external isDelegateCall {
        IFund(address(this)).enableModule(module);
    }

    /// @notice called by the fund
    function addModuleWithRoles(address module, uint256 roles) external isDelegateCall {
        IFund(address(this)).enableModule(module);
        IFund(address(this)).grantRoles(module, roles);
    }
}
