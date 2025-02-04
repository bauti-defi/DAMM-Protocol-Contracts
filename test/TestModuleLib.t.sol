// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "@forge-std/Test.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
import {ISafe, Enum} from "@src/interfaces/ISafe.sol";
import {IModuleLib} from "@src/interfaces/IModuleLib.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {SafeUtils} from "@test/utils/SafeUtils.sol";
import {Create2} from "@openzeppelin-contracts/utils/Create2.sol";
import {CreateCall} from "@safe-contracts/libraries/CreateCall.sol";
import "@src/libs/Errors.sol";

contract MockModule {
    address internal owner;

    constructor(address _owner) {
        owner = _owner;
    }
}

contract TestModuleLib is TestBaseProtocol, TestBaseGnosis {
    address internal fundAdmin;
    uint256 internal fundAdminPK;
    ISafe internal fund;

    function setUp() public override(TestBaseProtocol, TestBaseGnosis) {
        TestBaseProtocol.setUp();
        TestBaseGnosis.setUp();

        (fundAdmin, fundAdminPK) = makeAddrAndKey("FundAdmin");
        vm.deal(fundAdmin, 1000 ether);

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;

        fund = ISafe(address(deploySafe(admins, 1, 1)));
        vm.label(address(fund), "Fund");
        assertTrue(address(fund) != address(0), "Failed to deploy fund");
        assertTrue(fund.isOwner(fundAdmin), "Fund admin not owner");

        vm.deal(address(fund), 1000 ether);
    }

    function test_deploy_module() public {
        bytes memory creationCode =
            abi.encodePacked(type(MockModule).creationCode, abi.encode(address(fund)));

        bytes memory transaction = abi.encodeWithSelector(
            IModuleLib.deployModule.selector, bytes32("salt"), 0, creationCode
        );

        bytes memory transactionData = fund.encodeTransactionData(
            address(moduleLib),
            0,
            transaction,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            fund.nonce()
        );

        bytes memory transactionSignature =
            SafeUtils.buildSafeSignatures(abi.encode(fundAdminPK), keccak256(transactionData), 1);

        vm.startPrank(fundAdmin, fundAdmin);
        bool success = fund.execTransaction(
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

        assertTrue(success, "Failed to deploy module");

        assertTrue(
            fund.isModuleEnabled(
                Create2.computeAddress(bytes32("salt"), keccak256(creationCode), address(fund))
            ),
            "Module not enabled"
        );
    }

    function test_deploy_module_must_be_delegatecall() public {
        bytes memory creationCode =
            abi.encodePacked(type(MockModule).creationCode, abi.encode(address(fund)));

        bytes memory transaction = abi.encodeWithSelector(
            IModuleLib.deployModule.selector, bytes32("salt"), 0, creationCode
        );

        bytes memory transactionData = fund.encodeTransactionData(
            address(moduleLib),
            0,
            transaction,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            fund.nonce()
        );

        bytes memory transactionSignature =
            SafeUtils.buildSafeSignatures(abi.encode(fundAdminPK), keccak256(transactionData), 1);

        vm.startPrank(fundAdmin, fundAdmin);
        vm.expectRevert();
        fund.execTransaction(
            address(moduleLib),
            0,
            transaction,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            transactionSignature
        );
        vm.stopPrank();
    }
}
