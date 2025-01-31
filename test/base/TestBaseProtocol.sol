// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "@forge-std/Test.sol";
import {ModuleLib} from "@src/libs/ModuleLib.sol";
import {Safe} from "@safe-contracts/Safe.sol";
import {Enum} from "@src/interfaces/ISafe.sol";
import {SafeUtils} from "@test/utils/SafeUtils.sol";
import "@openzeppelin-contracts/utils/Create2.sol";

interface ICreateCall {
    function performCreate2(uint256 value, bytes memory deploymentData, bytes32 salt)
        external
        returns (address newContract);
}

abstract contract TestBaseProtocol is Test {
    ModuleLib internal moduleLib;

    function setUp() public virtual {
        moduleLib = new ModuleLib();
        vm.label(address(moduleLib), "ModuleLib");
    }

    function deployContract(
        address payable fund,
        address admin,
        uint256 adminPK,
        address createCall,
        bytes32 creationSalt,
        uint256 valueToForward,
        bytes memory contractCreationCode
    ) internal returns (address deployed) {
        bytes memory transaction = abi.encodeWithSelector(
            ICreateCall.performCreate2.selector, valueToForward, contractCreationCode, creationSalt
        );

        Safe safe = Safe(fund);

        bytes memory transactionData = safe.encodeTransactionData(
            address(createCall),
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
            address(createCall),
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

        deployed = Create2.computeAddress(creationSalt, keccak256(contractCreationCode), fund);
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

        deployedModule = Create2.computeAddress(creationSalt, keccak256(moduleCreationCode), fund);

        assertTrue(safe.isModuleEnabled(deployedModule), "Module not enabled");
    }
}
