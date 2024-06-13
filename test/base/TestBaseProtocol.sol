// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "@forge-std/Test.sol";
import {ModuleLib} from "@src/libs/ModuleLib.sol";
import {Safe} from "@safe-contracts/Safe.sol";
import {Enum} from "@src/interfaces/ISafe.sol";
import {SafeUtils} from "@test/utils/SafeUtils.sol";
import {IOwnable} from "@src/interfaces/IOwnable.sol";
import {DeployContract} from "@src/libs/DeployContract.sol";

abstract contract TestBaseProtocol is Test {
    ModuleLib internal moduleLib;
    DeployContract internal deployContractLib;

    function setUp() public virtual {
        moduleLib = new ModuleLib();
        vm.label(address(moduleLib), "ModuleLib");

        deployContractLib = new DeployContract();
        vm.label(address(deployContractLib), "DeployContract");
    }

    function deployContract(
        address payable fund,
        address admin,
        uint256 adminPK,
        bytes32 creationSalt,
        uint256 valueToForward,
        bytes memory contractCreationCode
    ) internal returns (address deployed) {
        bytes memory transaction = abi.encodeWithSelector(
            DeployContract.deployContract.selector,
            creationSalt,
            valueToForward,
            contractCreationCode
        );

        Safe safe = Safe(fund);

        bytes memory transactionData = safe.encodeTransactionData(
            address(deployContractLib),
            valueToForward,
            transaction,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            safe.nonce()
        );

        bytes memory transactionSignature =
            SafeUtils.buildSafeSignatures(abi.encode(adminPK), keccak256(transactionData), 1);

        vm.startPrank(admin, admin);
        bool success = safe.execTransaction(
            address(deployContractLib),
            valueToForward,
            transaction,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            transactionSignature
        );
        vm.stopPrank();

        assertTrue(success, "Failed to deploy contract");

        deployed =
            deployContractLib.computeAddress(creationSalt, keccak256(contractCreationCode), fund);
    }

    function deployModule(
        address payable fund,
        address admin,
        uint256 adminPK,
        bytes32 creationSalt,
        uint256 valueToForward,
        bytes memory moduleCreationCode
    ) internal returns (address deployedModule) {
        bytes memory transaction = abi.encodeWithSelector(
            ModuleLib.deployModule.selector, creationSalt, valueToForward, moduleCreationCode
        );

        Safe safe = Safe(fund);

        bytes memory transactionData = safe.encodeTransactionData(
            address(moduleLib),
            valueToForward,
            transaction,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            safe.nonce()
        );

        bytes memory transactionSignature =
            SafeUtils.buildSafeSignatures(abi.encode(adminPK), keccak256(transactionData), 1);

        vm.startPrank(admin, admin);
        bool success = safe.execTransaction(
            address(moduleLib),
            valueToForward,
            transaction,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            transactionSignature
        );
        vm.stopPrank();

        assertTrue(success, "Failed to deploy module");

        deployedModule =
            deployContractLib.computeAddress(creationSalt, keccak256(moduleCreationCode), fund);

        assertTrue(safe.isModuleEnabled(deployedModule), "Module not enabled");
    }

    function deployModuleWithRoles(
        address payable fund,
        address admin,
        uint256 adminPK,
        bytes32 creationSalt,
        uint256 valueToForward,
        bytes memory moduleCreationCode,
        uint256 roles
    ) internal returns (address deployedModule) {
        bytes memory transaction = abi.encodeWithSelector(
            ModuleLib.deployModuleWithRoles.selector,
            creationSalt,
            valueToForward,
            moduleCreationCode,
            roles
        );

        Safe safe = Safe(fund);

        {
            bytes memory transactionData = safe.encodeTransactionData(
                address(moduleLib),
                valueToForward,
                transaction,
                Enum.Operation.DelegateCall,
                0,
                0,
                0,
                address(0),
                payable(address(0)),
                safe.nonce()
            );

            bytes memory transactionSignature =
                SafeUtils.buildSafeSignatures(abi.encode(adminPK), keccak256(transactionData), 1);

            vm.startPrank(admin, admin);
            bool success = safe.execTransaction(
                address(moduleLib),
                valueToForward,
                transaction,
                Enum.Operation.DelegateCall,
                0,
                0,
                0,
                address(0),
                payable(address(0)),
                transactionSignature
            );
            vm.stopPrank();

            assertTrue(success, "Failed to deploy module with roles");
        }

        deployedModule =
            deployContractLib.computeAddress(creationSalt, keccak256(moduleCreationCode), fund);

        assertTrue(safe.isModuleEnabled(deployedModule), "Module not enabled");
        assertTrue(IOwnable(address(fund)).hasAllRoles(deployedModule, roles), "Roles not set");
    }

    function addModuleWithRoles(
        address payable fund,
        address admin,
        uint256 adminPK,
        address module,
        uint256 roles
    ) internal {
        bytes memory transaction =
            abi.encodeWithSelector(ModuleLib.addModuleWithRoles.selector, module, roles);

        Safe safe = Safe(fund);

        bytes memory transactionData = safe.encodeTransactionData(
            address(moduleLib),
            0,
            transaction,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            safe.nonce()
        );

        bytes memory transactionSignature =
            SafeUtils.buildSafeSignatures(abi.encode(adminPK), keccak256(transactionData), 1);

        vm.startPrank(admin, admin);
        bool success = safe.execTransaction(
            address(moduleLib),
            0,
            transaction,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            transactionSignature
        );
        vm.stopPrank();

        assertTrue(success, "Failed to add module with roles");

        assertTrue(safe.isModuleEnabled(module), "Module not enabled");
        assertTrue(IOwnable(address(fund)).hasAllRoles(module, roles), "Roles not set");
    }
}
