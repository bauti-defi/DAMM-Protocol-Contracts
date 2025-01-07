// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {IFund} from "@src/interfaces/IFund.sol";
import {FundFactory} from "@src/FundFactory.sol";
import {EulerRouter} from "@euler-price-oracle/EulerRouter.sol";
import {Periphery} from "@src/modules/deposit/Periphery.sol";
import {IPeriphery} from "@src/interfaces/IPeriphery.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {HookConfig} from "@src/modules/transact/Structs.sol";
import "@src/modules/deposit/Structs.sol";
import {HookRegistry} from "@src/modules/transact/HookRegistry.sol";
import {TransactionModule} from "@src/modules/transact/TransactionModule.sol";
import {VaultConnectorHook} from "@src/hooks/damm/VaultConnectorHook.sol";
import {TokenTransferCallValidator} from "@src/hooks/transfers/TokenTransferCallValidator.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";
import {FundValuationOracle} from "@src/oracles/FundValuationOracle.sol";
import {MotherFundValuationOracle} from "@src/oracles/MotherFundValuationOracle.sol";
import {MockPriceOracle} from "@test/mocks/MockPriceOracle.sol";

/// This contract will test a full deployment of 2 funds with child funds included.
/// Fund A (mother) will have two child funds. Fund B (mother) will have 2 childs funds.
/// Fund A will have deposits in fund B. Fund B will not be aware of Fund A.
/// The goal of this integration test is to validate that funds can correctly integrate with each other
/// and that valuation of fund assets works correctly.
/// No strategies will be deployed in this test => no protocols will be integrated.
/// The only hooks to use are the vault connector for deposits and withdrawals of Fund A to Fund B.
/// And the transfer hook for transfering assets to and from child funds.
contract TestFundIntegration is TestBaseGnosis, TestBaseProtocol {
    uint8 constant VALUATION_DECIMALS = 18;
    uint256 constant VAULT_DECIMAL_OFFSET = 1;

    address internal protocolAdmin;
    uint256 internal protocolAdminPK;

    address internal feeRecipient;
    address internal operator;

    MockERC20 internal mockToken0;
    MockERC20 internal mockToken1;
    IFund internal fundA;
    IFund internal fundB;
    IFund internal fundAChild1;
    IFund internal fundAChild2;
    IFund internal fundBChild1;
    IFund internal fundBChild2;
    FundFactory internal fundFactory;

    Periphery internal peripheryA;
    Periphery internal peripheryB;

    HookRegistry internal hookRegistryA;
    HookRegistry internal hookRegistryB;

    VaultConnectorHook internal vaultConnectorA;

    TokenTransferCallValidator internal transferHookA;
    TokenTransferCallValidator internal transferHookB;

    TransactionModule internal transactionModuleA;
    TransactionModule internal transactionModuleB;

    EulerRouter internal oracleRouter;

    function setUp() public virtual override(TestBaseGnosis, TestBaseProtocol) {
        TestBaseGnosis.setUp();
        TestBaseProtocol.setUp();

        feeRecipient = makeAddr("FeeRecipient");
        operator = makeAddr("Operator");
        (protocolAdmin, protocolAdminPK) = makeAddrAndKey("ProtocolAdmin");

        mockToken0 = new MockERC20(18);
        mockToken1 = new MockERC20(18);

        fundFactory = new FundFactory();
        vm.label(address(fundFactory), "FundFactory");

        address[] memory admins = new address[](1);
        admins[0] = protocolAdmin;

        fundA =
            fundFactory.deployFund(address(safeProxyFactory), address(safeSingleton), admins, 1, 1);
        vm.label(address(fundA), "FundA");

        fundAChild1 =
            fundFactory.deployFund(address(safeProxyFactory), address(safeSingleton), admins, 2, 1);
        vm.label(address(fundAChild1), "FundAChild1");

        fundAChild2 =
            fundFactory.deployFund(address(safeProxyFactory), address(safeSingleton), admins, 3, 1);
        vm.label(address(fundAChild2), "FundAChild2");

        fundB =
            fundFactory.deployFund(address(safeProxyFactory), address(safeSingleton), admins, 4, 1);
        vm.label(address(fundB), "FundB");

        fundBChild1 =
            fundFactory.deployFund(address(safeProxyFactory), address(safeSingleton), admins, 5, 1);
        vm.label(address(fundBChild1), "FundBChild1");

        fundBChild2 =
            fundFactory.deployFund(address(safeProxyFactory), address(safeSingleton), admins, 6, 1);
        vm.label(address(fundBChild2), "FundBChild2");

        /// TODO: check if we should be deploying the oracle router as fund or admin
        /// this depends on if the router will be shared, which it should be for convinience
        vm.prank(protocolAdmin);
        oracleRouter = new EulerRouter(address(1), address(protocolAdmin));
        vm.label(address(oracleRouter), "OracleRouter");

        // deploy periphery using module factory
        peripheryA = Periphery(
            deployModule(
                payable(address(fundA)),
                protocolAdmin,
                protocolAdminPK,
                bytes32("peripheryA"),
                0,
                abi.encodePacked(
                    type(Periphery).creationCode,
                    abi.encode(
                        "PeripheryA",
                        "PA",
                        VALUATION_DECIMALS, // must be same as underlying oracles response denomination
                        payable(address(fundA)),
                        address(oracleRouter),
                        address(fundA),
                        /// fund is admin
                        feeRecipient,
                        0
                    )
                )
            )
        );

        assertTrue(fundA.isModuleEnabled(address(peripheryA)), "PeripheryA is not module");

        // deploy hook registry and transaction module for Fund A
        hookRegistryA = HookRegistry(
            deployContract(
                payable(address(fundA)),
                protocolAdmin,
                protocolAdminPK,
                address(createCall),
                bytes32("hookRegistryA"),
                0,
                abi.encodePacked(type(HookRegistry).creationCode, abi.encode(address(fundA)))
            )
        );

        vm.label(address(hookRegistryA), "HookRegistryA");

        // deploy transaction module for Fund A
        transactionModuleA = TransactionModule(
            deployModule(
                payable(address(fundA)),
                protocolAdmin,
                protocolAdminPK,
                bytes32("transactionModuleA"),
                0,
                abi.encodePacked(
                    type(TransactionModule).creationCode,
                    abi.encode(address(fundA), address(hookRegistryA))
                )
            )
        );
        vm.label(address(transactionModuleA), "TransactionModuleA");

        assertEq(transactionModuleA.fund(), address(fundA), "TransactionModuleA fund not set");

        // now we deploy the vault connector for Fund A
        vaultConnectorA = new VaultConnectorHook(address(fundA));
        vm.label(address(vaultConnectorA), "VaultConnectorA");

        // now we deploy the transfer hook for Fund A
        transferHookA = new TokenTransferCallValidator(address(fundA));
        vm.label(address(transferHookA), "TransferHookA");

        peripheryB = Periphery(
            deployModule(
                payable(address(fundB)),
                protocolAdmin,
                protocolAdminPK,
                bytes32("peripheryB"),
                0,
                abi.encodePacked(
                    type(Periphery).creationCode,
                    abi.encode(
                        "PeripheryB",
                        "PB",
                        VALUATION_DECIMALS, // must be same as underlying oracles response denomination
                        payable(address(fundB)),
                        address(oracleRouter),
                        address(fundB),
                        /// fund is admin
                        feeRecipient,
                        0
                    )
                )
            )
        );

        assertTrue(fundB.isModuleEnabled(address(peripheryB)), "PeripheryB is not module");

        // deploy hook registry and transaction module for Fund B
        hookRegistryB = HookRegistry(
            deployContract(
                payable(address(fundB)),
                protocolAdmin,
                protocolAdminPK,
                address(createCall),
                bytes32("hookRegistryB"),
                0,
                abi.encodePacked(type(HookRegistry).creationCode, abi.encode(address(fundB)))
            )
        );

        vm.label(address(hookRegistryB), "HookRegistryB");

        // deploy transaction module for Fund B
        transactionModuleB = TransactionModule(
            deployModule(
                payable(address(fundB)),
                protocolAdmin,
                protocolAdminPK,
                bytes32("transactionModuleB"),
                0,
                abi.encodePacked(
                    type(TransactionModule).creationCode,
                    abi.encode(address(fundB), address(hookRegistryB))
                )
            )
        );
        vm.label(address(transactionModuleB), "TransactionModuleB");

        assertEq(transactionModuleB.fund(), address(fundB), "TransactionModuleB fund not set");

        // now we deploy the transfer hook for Fund B
        transferHookB = new TokenTransferCallValidator(address(fundB));
        vm.label(address(transferHookB), "TransferHookB");

        /// ALL THE INFRA IS DEPLOYED, NOW WE MUST CONFIGURE IT

        // configure the vault connector for Fund A
        // deposit from Fund A to Fund B
        vm.startPrank(address(fundA));
        hookRegistryA.setHooks(
            HookConfig({
                operator: address(operator),
                target: address(peripheryB),
                beforeTrxHook: address(vaultConnectorA),
                afterTrxHook: address(0),
                targetSelector: IPeriphery.deposit.selector,
                operation: uint8(Enum.Operation.Call)
            })
        );

        // withdraw from Fund B to Fund A
        hookRegistryA.setHooks(
            HookConfig({
                operator: address(operator),
                target: address(peripheryB),
                beforeTrxHook: address(vaultConnectorA),
                afterTrxHook: address(0),
                targetSelector: IPeriphery.withdraw.selector,
                operation: uint8(Enum.Operation.Call)
            })
        );

        // configure the token transfer hook for Fund A to its children funds
        // need to configure for both mockToken0 and mockToken1

        // configure child funds for Fund A
        fundA.addChildFund(address(fundAChild1));
        fundA.addChildFund(address(fundAChild2));

        // configure mock tokens as assets of interest for Fund A
        fundA.setAssetOfInterest(address(mockToken0));
        // also enable assets on the periphery for Fund A
        peripheryA.enableAsset(
            address(mockToken0),
            AssetPolicy({
                minimumDeposit: 100,
                minimumWithdrawal: 100,
                canDeposit: true,
                canWithdraw: true,
                permissioned: false,
                enabled: true
            })
        );
        fundA.setAssetOfInterest(address(mockToken1));

        // transfer from Fund A to Fund A Child 1
        hookRegistryA.setHooks(
            HookConfig({
                operator: address(operator),
                target: address(mockToken0),
                beforeTrxHook: address(transferHookA),
                afterTrxHook: address(0),
                targetSelector: IERC20.transfer.selector,
                operation: uint8(Enum.Operation.Call)
            })
        );
        hookRegistryA.setHooks(
            HookConfig({
                operator: address(operator),
                target: address(mockToken1),
                beforeTrxHook: address(transferHookA),
                afterTrxHook: address(0),
                targetSelector: IERC20.transfer.selector,
                operation: uint8(Enum.Operation.Call)
            })
        );

        hookRegistryA.setHooks(
            HookConfig({
                operator: address(operator),
                target: address(mockToken0),
                beforeTrxHook: address(transferHookA),
                afterTrxHook: address(0),
                targetSelector: IERC20.transferFrom.selector,
                operation: uint8(Enum.Operation.Call)
            })
        );
        hookRegistryA.setHooks(
            HookConfig({
                operator: address(operator),
                target: address(mockToken1),
                beforeTrxHook: address(transferHookA),
                afterTrxHook: address(0),
                targetSelector: IERC20.transferFrom.selector,
                operation: uint8(Enum.Operation.Call)
            })
        );

        // configure the transfer hook for Fund A
        transferHookA.enableTransfer(
            address(mockToken0), address(fundAChild1), address(fundA), IERC20.transfer.selector
        );
        transferHookA.enableTransfer(
            address(mockToken1), address(fundAChild1), address(fundA), IERC20.transfer.selector
        );
        transferHookA.enableTransfer(
            address(mockToken0), address(fundAChild2), address(fundA), IERC20.transfer.selector
        );
        transferHookA.enableTransfer(
            address(mockToken1), address(fundAChild2), address(fundA), IERC20.transfer.selector
        );
        transferHookA.enableTransfer(
            address(mockToken0), address(fundAChild1), address(fundA), IERC20.transferFrom.selector
        );
        transferHookA.enableTransfer(
            address(mockToken1), address(fundAChild1), address(fundA), IERC20.transferFrom.selector
        );
        transferHookA.enableTransfer(
            address(mockToken0), address(fundAChild2), address(fundA), IERC20.transferFrom.selector
        );
        transferHookA.enableTransfer(
            address(mockToken1), address(fundAChild2), address(fundA), IERC20.transferFrom.selector
        );

        vm.stopPrank();

        // configure child funds for Fund B
        vm.startPrank(address(fundB));
        fundB.addChildFund(address(fundBChild1));
        fundB.addChildFund(address(fundBChild2));

        // configure mock tokens as assets of interest for Fund B
        fundB.setAssetOfInterest(address(mockToken0));
        // also enable assets on the periphery for Fund B
        peripheryB.enableAsset(
            address(mockToken0),
            AssetPolicy({
                minimumDeposit: 100,
                minimumWithdrawal: 100,
                canDeposit: true,
                canWithdraw: true,
                permissioned: false,
                enabled: true
            })
        );
        fundB.setAssetOfInterest(address(mockToken1));

        // transfer from Fund B to Fund B Child 1
        hookRegistryB.setHooks(
            HookConfig({
                operator: address(operator),
                target: address(mockToken0),
                beforeTrxHook: address(transferHookB),
                afterTrxHook: address(0),
                targetSelector: IERC20.transfer.selector,
                operation: uint8(Enum.Operation.Call)
            })
        );

        hookRegistryB.setHooks(
            HookConfig({
                operator: address(operator),
                target: address(mockToken0),
                beforeTrxHook: address(transferHookB),
                afterTrxHook: address(0),
                targetSelector: IERC20.transferFrom.selector,
                operation: uint8(Enum.Operation.Call)
            })
        );

        hookRegistryB.setHooks(
            HookConfig({
                operator: address(operator),
                target: address(mockToken1),
                beforeTrxHook: address(transferHookB),
                afterTrxHook: address(0),
                targetSelector: IERC20.transfer.selector,
                operation: uint8(Enum.Operation.Call)
            })
        );

        hookRegistryB.setHooks(
            HookConfig({
                operator: address(operator),
                target: address(mockToken1),
                beforeTrxHook: address(transferHookB),
                afterTrxHook: address(0),
                targetSelector: IERC20.transferFrom.selector,
                operation: uint8(Enum.Operation.Call)
            })
        );

        // configure the transfer hook for Fund B
        transferHookB.enableTransfer(
            address(mockToken0), address(fundBChild1), address(fundB), IERC20.transfer.selector
        );
        transferHookB.enableTransfer(
            address(mockToken1), address(fundBChild1), address(fundB), IERC20.transfer.selector
        );
        transferHookB.enableTransfer(
            address(mockToken0), address(fundBChild2), address(fundB), IERC20.transfer.selector
        );
        transferHookB.enableTransfer(
            address(mockToken1), address(fundBChild2), address(fundB), IERC20.transfer.selector
        );
        transferHookB.enableTransfer(
            address(mockToken0), address(fundBChild1), address(fundB), IERC20.transferFrom.selector
        );
        transferHookB.enableTransfer(
            address(mockToken1), address(fundBChild1), address(fundB), IERC20.transferFrom.selector
        );
        transferHookB.enableTransfer(
            address(mockToken0), address(fundBChild2), address(fundB), IERC20.transferFrom.selector
        );
        transferHookB.enableTransfer(
            address(mockToken1), address(fundBChild2), address(fundB), IERC20.transferFrom.selector
        );

        vm.stopPrank();

        // now configure the oracles
        address unitOfAccountA = address(peripheryA.unitOfAccount());
        address unitOfAccountB = address(peripheryB.unitOfAccount());

        MotherFundValuationOracle motherValuationOracleA = new MotherFundValuationOracle(address(oracleRouter));
        vm.label(address(motherValuationOracleA), "MotherFundValuationOracleA");
        vm.prank(address(protocolAdmin));
        oracleRouter.govSetConfig(address(fundA), unitOfAccountA, address(motherValuationOracleA));

       
    }

    function test_working() public {
        assert(true);
    }
}
