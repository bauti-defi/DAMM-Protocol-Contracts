// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "@forge-std/Test.sol";
import {ModuleFactory} from "@src/ModuleFactory.sol";
import {Safe} from "@safe-contracts/Safe.sol";
import {Enum} from "@src/interfaces/ISafe.sol";
import {SafeUtils} from "@test/utils/SafeUtils.sol";

abstract contract TestBaseProtocol is Test {
    ModuleFactory internal moduleFactory;

    function setUp() public virtual {
        moduleFactory = new ModuleFactory();
        vm.label(address(moduleFactory), "ModuleFactory");
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
            ModuleFactory.deployContract.selector,
            creationSalt,
            valueToForward,
            contractCreationCode
        );

        Safe safe = Safe(fund);

        bytes memory transactionData = safe.encodeTransactionData(
            address(moduleFactory),
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
            address(moduleFactory),
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

        deployed = moduleFactory.computeAddress(creationSalt, keccak256(contractCreationCode), fund);
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
            ModuleFactory.deployModule.selector, creationSalt, valueToForward, moduleCreationCode
        );

        Safe safe = Safe(fund);

        bytes memory transactionData = safe.encodeTransactionData(
            address(moduleFactory),
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
            address(moduleFactory),
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
            moduleFactory.computeAddress(creationSalt, keccak256(moduleCreationCode), fund);

        assertTrue(safe.isModuleEnabled(deployedModule), "Module not enabled");
    }
}
