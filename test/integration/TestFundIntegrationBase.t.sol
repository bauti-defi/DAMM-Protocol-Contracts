// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import {Test} from "forge-std/Test.sol";
// import {console2} from "forge-std/console2.sol";
// import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
// import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
// import {EulerRouter} from "@euler-price-oracle/EulerRouter.sol";
// import {FixedRateOracle} from "@euler-price-oracle/adapter/fixed/FixedRateOracle.sol";
// import {Periphery} from "@src/modules/deposit/Periphery.sol";
// import {IPeriphery} from "@src/interfaces/IPeriphery.sol";
// import {Enum} from "@safe-contracts/common/Enum.sol";
// import {HookConfig} from "@src/modules/transact/Structs.sol";
// import "@src/modules/deposit/Structs.sol";
// import {HookRegistry} from "@src/modules/transact/HookRegistry.sol";
// import {TransactionModule} from "@src/modules/transact/TransactionModule.sol";
// import {VaultConnectorHook} from "@src/hooks/damm/VaultConnectorHook.sol";
// import {TokenTransferCallValidator} from "@src/hooks/transfers/TokenTransferCallValidator.sol";
// import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
// import {ChainlinkOracle} from "@euler-price-oracle/adapter/chainlink/ChainlinkOracle.sol";
// import {
//     ARB_USDC_USD_FEED,
//     ARB_USDT_USD_FEED,
//     ARB_DAI_USD_FEED,
//     ARB_ETH_USD_FEED
// } from "@test/forked/ChainlinkOracleFeeds.sol";
// import {TokenMinter} from "@test/forked/TokenMinter.sol";
// import {MockERC20} from "@test/mocks/MockERC20.sol";
// import "@src/modules/transact/Structs.sol";
// import {ISafe} from "@src/interfaces/ISafe.sol";

// abstract contract TestFundIntegrationBase is TestBaseGnosis, TestBaseProtocol, TokenMinter {
//     uint8 constant VALUATION_DECIMALS = 18;
//     uint8 constant TRUSTED_ORACLE_PRECISION = VALUATION_DECIMALS - 1;
//     uint256 constant VAULT_DECIMAL_OFFSET = 1;
//     uint256 constant SCALAR = 10 ** 6;

//     uint256 internal arbitrumFork;

//     address internal protocolAdmin;
//     uint256 internal protocolAdminPK;

//     address internal feeRecipient;
//     address internal operator;
//     address internal broker;

//     ISafe internal fundA;
//     ISafe internal fundB;
//     ISafe internal fundAChild1;
//     ISafe internal fundAChild2;
//     ISafe internal fundBChild1;
//     ISafe internal fundBChild2;

//     Periphery internal peripheryA;
//     Periphery internal peripheryB;

//     HookRegistry internal hookRegistryA;
//     HookRegistry internal hookRegistryB;

//     VaultConnectorHook internal vaultConnectorA;

//     TokenTransferCallValidator internal transferHookA;
//     TokenTransferCallValidator internal transferHookB;

//     TransactionModule internal transactionModuleA;
//     TransactionModule internal transactionModuleB;

//     EulerRouter internal oracleRouter;

//     uint256 internal brokerAId;
//     uint256 internal brokerBId;
//     uint256 internal fundABrokerId;

//     uint256 internal nonce;

//     function setUp() public virtual override(TestBaseGnosis, TestBaseProtocol, TokenMinter) {
//         _setupFork();
//         _setupBase();
//         _deployFunds();
//         _deployInfrastructure();
//         _configureHooksAndPolicies();
//     }

//     function _setupFork() internal {
//         arbitrumFork = vm.createFork(vm.envString("ARBI_RPC_URL"));
//         vm.selectFork(arbitrumFork);
//         assertEq(vm.activeFork(), arbitrumFork);
//         vm.rollFork(218796378);
//     }

//     function _setupBase() internal {
//         TestBaseGnosis.setUp();
//         TestBaseProtocol.setUp();
//         TokenMinter.setUp();

//         feeRecipient = makeAddr("FeeRecipient");
//         operator = makeAddr("Operator");
//         broker = makeAddr("Broker");
//         (protocolAdmin, protocolAdminPK) = makeAddrAndKey("ProtocolAdmin");
//     }

//     function _deployFunds() internal {
//         address[] memory admins = new address[](1);
//         admins[0] = protocolAdmin;

//         // Deploy Fund A and its children
//         fundA = ISafe(address(deploySafe(admins, 1, ++nonce)));
//         vm.label(address(fundA), "FundA");

//         fundAChild1 = ISafe(address(deploySafe(admins, 1, ++nonce)));
//         vm.label(address(fundAChild1), "FundAChild1");

//         fundAChild2 = ISafe(address(deploySafe(admins, 1, ++nonce)));
//         vm.label(address(fundAChild2), "FundAChild2");

//         // Deploy Fund B and its children
//         fundB = ISafe(address(deploySafe(admins, 1, ++nonce)));
//         vm.label(address(fundB), "FundB");

//         fundBChild1 = ISafe(address(deploySafe(admins, 1, ++nonce)));
//         vm.label(address(fundBChild1), "FundBChild1");

//         fundBChild2 = ISafe(address(deploySafe(admins, 1, ++nonce)));
//         vm.label(address(fundBChild2), "FundBChild2");
//     }

//     function _deployInfrastructure() internal {
//         _deployOracleRouter();
//         _deployPeriphery();
//         _deployHooksAndTransactionModules();
//     }

//     function _deployOracleRouter() internal {
//         vm.prank(protocolAdmin);
//         oracleRouter = new EulerRouter(address(1), address(protocolAdmin));
//         vm.label(address(oracleRouter), "OracleRouter");
//     }

//     function _deployPeriphery() internal {
//         // Deploy periphery A
//         peripheryA = Periphery(
//             deployModule(
//                 payable(address(fundA)),
//                 protocolAdmin,
//                 protocolAdminPK,
//                 bytes32("peripheryA"),
//                 0,
//                 abi.encodePacked(
//                     type(Periphery).creationCode,
//                     abi.encode(
//                         "PeripheryA",
//                         "PA",
//                         VALUATION_DECIMALS,
//                         payable(address(fundA)),
//                         address(oracleRouter),
//                         address(fundA),
//                         feeRecipient
//                     )
//                 )
//             )
//         );
//         vm.label(address(peripheryA), "PeripheryA");
//         assertTrue(fundA.isModuleEnabled(address(peripheryA)), "PeripheryA is not module");

//         // Deploy periphery B
//         peripheryB = Periphery(
//             deployModule(
//                 payable(address(fundB)),
//                 protocolAdmin,
//                 protocolAdminPK,
//                 bytes32("peripheryB"),
//                 0,
//                 abi.encodePacked(
//                     type(Periphery).creationCode,
//                     abi.encode(
//                         "PeripheryB",
//                         "PB",
//                         VALUATION_DECIMALS,
//                         payable(address(fundB)),
//                         address(oracleRouter),
//                         address(fundB),
//                         feeRecipient
//                     )
//                 )
//             )
//         );
//         vm.label(address(peripheryB), "PeripheryB");
//         assertTrue(fundB.isModuleEnabled(address(peripheryB)), "PeripheryB is not module");
//     }

//     function _deployHooksAndTransactionModules() internal {
//         _deployFundAHooksAndModules();
//         _deployFundBHooksAndModules();
//     }

//     function _deployFundAHooksAndModules() internal {
//         // Deploy hook registry
//         hookRegistryA = HookRegistry(
//             deployContract(
//                 payable(address(fundA)),
//                 protocolAdmin,
//                 protocolAdminPK,
//                 address(createCall),
//                 bytes32("hookRegistryA"),
//                 0,
//                 abi.encodePacked(type(HookRegistry).creationCode, abi.encode(address(fundA)))
//             )
//         );
//         vm.label(address(hookRegistryA), "HookRegistryA");

//         // Deploy transaction module
//         transactionModuleA = TransactionModule(
//             deployModule(
//                 payable(address(fundA)),
//                 protocolAdmin,
//                 protocolAdminPK,
//                 bytes32("transactionModuleA"),
//                 0,
//                 abi.encodePacked(
//                     type(TransactionModule).creationCode,
//                     abi.encode(address(fundA), address(hookRegistryA))
//                 )
//             )
//         );
//         vm.label(address(transactionModuleA), "TransactionModuleA");
//         assertEq(transactionModuleA.fund(), address(fundA), "TransactionModuleA fund not set");

//         // Deploy hooks
//         vaultConnectorA = new VaultConnectorHook(address(fundA));
//         vm.label(address(vaultConnectorA), "VaultConnectorA");

//         transferHookA = new TokenTransferCallValidator(address(fundA));
//         vm.label(address(transferHookA), "TransferHookA");
//     }

//     function _deployFundBHooksAndModules() internal {
//         // Deploy hook registry
//         hookRegistryB = HookRegistry(
//             deployContract(
//                 payable(address(fundB)),
//                 protocolAdmin,
//                 protocolAdminPK,
//                 address(createCall),
//                 bytes32("hookRegistryB"),
//                 0,
//                 abi.encodePacked(type(HookRegistry).creationCode, abi.encode(address(fundB)))
//             )
//         );
//         vm.label(address(hookRegistryB), "HookRegistryB");

//         // Deploy transaction module
//         transactionModuleB = TransactionModule(
//             deployModule(
//                 payable(address(fundB)),
//                 protocolAdmin,
//                 protocolAdminPK,
//                 bytes32("transactionModuleB"),
//                 0,
//                 abi.encodePacked(
//                     type(TransactionModule).creationCode,
//                     abi.encode(address(fundB), address(hookRegistryB))
//                 )
//             )
//         );
//         vm.label(address(transactionModuleB), "TransactionModuleB");
//         assertEq(transactionModuleB.fund(), address(fundB), "TransactionModuleB fund not set");

//         // Deploy hooks
//         transferHookB = new TokenTransferCallValidator(address(fundB));
//         vm.label(address(transferHookB), "TransferHookB");
//     }

//     function _configureHooksAndPolicies() internal {
//         // configure the vault connector for Fund A
//         // deposit from Fund A to Fund B
//         vm.startPrank(address(fundA));
//         hookRegistryA.setHooks(
//             HookConfig({
//                 operator: address(operator),
//                 target: address(peripheryB),
//                 beforeTrxHook: address(vaultConnectorA),
//                 afterTrxHook: address(0),
//                 targetSelector: IPeriphery.deposit.selector,
//                 operation: uint8(Enum.Operation.Call)
//             })
//         );

//         // withdraw from Fund B to Fund A
//         hookRegistryA.setHooks(
//             HookConfig({
//                 operator: address(operator),
//                 target: address(peripheryB),
//                 beforeTrxHook: address(vaultConnectorA),
//                 afterTrxHook: address(0),
//                 targetSelector: IPeriphery.withdraw.selector,
//                 operation: uint8(Enum.Operation.Call)
//             })
//         );

//         // also enable assets on the periphery for Fund A
//         peripheryA.enableGlobalAssetPolicy(
//             ARB_USDC,
//             AssetPolicy({
//                 minimumDeposit: 100,
//                 minimumWithdrawal: 100,
//                 canDeposit: true,
//                 canWithdraw: true,
//                 enabled: true
//             })
//         );
//         peripheryA.enableGlobalAssetPolicy(
//             ARB_USDT,
//             AssetPolicy({
//                 minimumDeposit: 100,
//                 minimumWithdrawal: 100,
//                 canDeposit: true,
//                 canWithdraw: false,
//                 enabled: true
//             })
//         );

//         // transfer from Fund A to Fund A Child 1
//         hookRegistryA.setHooks(
//             HookConfig({
//                 operator: address(operator),
//                 target: ARB_USDC,
//                 beforeTrxHook: address(transferHookA),
//                 afterTrxHook: address(0),
//                 targetSelector: IERC20.transfer.selector,
//                 operation: uint8(Enum.Operation.Call)
//             })
//         );
//         hookRegistryA.setHooks(
//             HookConfig({
//                 operator: address(operator),
//                 target: ARB_USDT,
//                 beforeTrxHook: address(transferHookA),
//                 afterTrxHook: address(0),
//                 targetSelector: IERC20.transfer.selector,
//                 operation: uint8(Enum.Operation.Call)
//             })
//         );
//         hookRegistryA.setHooks(
//             HookConfig({
//                 operator: address(operator),
//                 target: ARB_USDC,
//                 beforeTrxHook: address(transferHookA),
//                 afterTrxHook: address(0),
//                 targetSelector: IERC20.transferFrom.selector,
//                 operation: uint8(Enum.Operation.Call)
//             })
//         );
//         hookRegistryA.setHooks(
//             HookConfig({
//                 operator: address(operator),
//                 target: ARB_USDT,
//                 beforeTrxHook: address(transferHookA),
//                 afterTrxHook: address(0),
//                 targetSelector: IERC20.transferFrom.selector,
//                 operation: uint8(Enum.Operation.Call)
//             })
//         );

//         // configure the transfer hook for Fund A
//         transferHookA.enableTransfer(
//             ARB_USDC, address(fundAChild1), address(fundA), IERC20.transfer.selector
//         );
//         transferHookA.enableTransfer(
//             ARB_USDT, address(fundAChild1), address(fundA), IERC20.transfer.selector
//         );
//         transferHookA.enableTransfer(
//             ARB_USDC, address(fundAChild2), address(fundA), IERC20.transfer.selector
//         );
//         transferHookA.enableTransfer(
//             ARB_USDT, address(fundAChild2), address(fundA), IERC20.transfer.selector
//         );
//         transferHookA.enableTransfer(
//             ARB_USDC, address(fundA), address(fundAChild1), IERC20.transferFrom.selector
//         );
//         transferHookA.enableTransfer(
//             ARB_USDT, address(fundA), address(fundAChild1), IERC20.transferFrom.selector
//         );
//         transferHookA.enableTransfer(
//             ARB_USDC, address(fundA), address(fundAChild2), IERC20.transferFrom.selector
//         );
//         transferHookA.enableTransfer(
//             ARB_USDT, address(fundA), address(fundAChild2), IERC20.transferFrom.selector
//         );

//         // enable the broker account for Fund A
//         brokerAId = peripheryA.openAccount(
//             CreateAccountParams({
//                 user: broker,
//                 brokerPerformanceFeeInBps: 0,
//                 protocolPerformanceFeeInBps: 0,
//                 brokerEntranceFeeInBps: 0,
//                 protocolEntranceFeeInBps: 0,
//                 brokerExitFeeInBps: 0,
//                 protocolExitFeeInBps: 0,
//                 transferable: false,
//                 ttl: 365 days,
//                 shareMintLimit: type(uint256).max,
//                 feeRecipient: address(0)
//             })
//         );

//         peripheryA.enableBrokerAssetPolicy(brokerAId, ARB_USDC, true);
//         peripheryA.enableBrokerAssetPolicy(brokerAId, ARB_USDC, false);
//         peripheryA.enableBrokerAssetPolicy(brokerAId, ARB_USDT, true);

//         // give periphery B allowance to deposit funds from Fund A
//         USDC.approve(address(peripheryB), type(uint256).max);
//         USDT.approve(address(peripheryB), type(uint256).max);
//         peripheryB.internalVault().approve(address(peripheryB), type(uint256).max);
//         vm.stopPrank();

//         // need to approve the mother fund to transfer funds from child funds
//         vm.startPrank(address(fundAChild1));
//         USDC.approve(address(fundA), type(uint256).max);
//         USDT.approve(address(fundA), type(uint256).max);
//         vm.stopPrank();

//         vm.startPrank(address(fundAChild2));
//         USDC.approve(address(fundA), type(uint256).max);
//         USDT.approve(address(fundA), type(uint256).max);
//         vm.stopPrank();

//         // we must mint a Fund B broker NFT to Fund A
//         vm.startPrank(address(fundB));
//         fundABrokerId = peripheryB.openAccount(
//             CreateAccountParams({
//                 user: address(fundA),
//                 brokerPerformanceFeeInBps: 0,
//                 protocolPerformanceFeeInBps: 0,
//                 brokerEntranceFeeInBps: 0,
//                 protocolEntranceFeeInBps: 0,
//                 brokerExitFeeInBps: 0,
//                 protocolExitFeeInBps: 0,
//                 transferable: false,
//                 ttl: 365 days,
//                 shareMintLimit: type(uint256).max,
//                 feeRecipient: address(0)
//             })
//         );
//         vm.stopPrank();

//         assertTrue(peripheryB.balanceOf(address(fundA)) > 0, "Fund A broker NFT not minted");
//         assertTrue(
//             peripheryB.ownerOf(fundABrokerId) == address(fundA), "Fund A broker NFT not minted"
//         );

//         // enable the broker account for Fund A
//         vm.prank(address(fundA));
//         vaultConnectorA.enableAccount(address(peripheryB), fundABrokerId);

//         assertTrue(
//             vaultConnectorA.isAccountEnabled(address(peripheryB), fundABrokerId),
//             "Broker account not enabled"
//         );

//         // configure child funds for Fund B
//         vm.startPrank(address(fundB));

//         // open broker account for Fund B
//         brokerBId = peripheryB.openAccount(
//             CreateAccountParams({
//                 user: broker,
//                 brokerPerformanceFeeInBps: 0,
//                 protocolPerformanceFeeInBps: 0,
//                 brokerEntranceFeeInBps: 0,
//                 protocolEntranceFeeInBps: 0,
//                 brokerExitFeeInBps: 0,
//                 protocolExitFeeInBps: 0,
//                 transferable: false,
//                 ttl: 365 days,
//                 shareMintLimit: type(uint256).max,
//                 feeRecipient: address(0)
//             })
//         );

//         // also enable assets on the periphery for Fund B
//         peripheryB.enableGlobalAssetPolicy(
//             ARB_USDC,
//             AssetPolicy({
//                 minimumDeposit: 100,
//                 minimumWithdrawal: 100,
//                 canDeposit: true,
//                 canWithdraw: true,
//                 enabled: true
//             })
//         );
//         peripheryB.enableGlobalAssetPolicy(
//             ARB_USDT,
//             AssetPolicy({
//                 minimumDeposit: 100,
//                 minimumWithdrawal: 100,
//                 canDeposit: true,
//                 canWithdraw: false,
//                 enabled: true
//             })
//         );

//         peripheryB.enableBrokerAssetPolicy(fundABrokerId, ARB_USDC, true);
//         peripheryB.enableBrokerAssetPolicy(fundABrokerId, ARB_USDC, false);
//         peripheryB.enableBrokerAssetPolicy(fundABrokerId, ARB_USDT, true);

//         // transfer from Fund B to Fund B Child 1
//         hookRegistryB.setHooks(
//             HookConfig({
//                 operator: address(operator),
//                 target: ARB_USDC,
//                 beforeTrxHook: address(transferHookB),
//                 afterTrxHook: address(0),
//                 targetSelector: IERC20.transfer.selector,
//                 operation: uint8(Enum.Operation.Call)
//             })
//         );

//         hookRegistryB.setHooks(
//             HookConfig({
//                 operator: address(operator),
//                 target: ARB_USDC,
//                 beforeTrxHook: address(transferHookB),
//                 afterTrxHook: address(0),
//                 targetSelector: IERC20.transferFrom.selector,
//                 operation: uint8(Enum.Operation.Call)
//             })
//         );

//         hookRegistryB.setHooks(
//             HookConfig({
//                 operator: address(operator),
//                 target: ARB_USDT,
//                 beforeTrxHook: address(transferHookB),
//                 afterTrxHook: address(0),
//                 targetSelector: IERC20.transfer.selector,
//                 operation: uint8(Enum.Operation.Call)
//             })
//         );

//         hookRegistryB.setHooks(
//             HookConfig({
//                 operator: address(operator),
//                 target: ARB_USDT,
//                 beforeTrxHook: address(transferHookB),
//                 afterTrxHook: address(0),
//                 targetSelector: IERC20.transferFrom.selector,
//                 operation: uint8(Enum.Operation.Call)
//             })
//         );

//         // configure the transfer hook for Fund B
//         transferHookB.enableTransfer(
//             ARB_USDC, address(fundBChild1), address(fundB), IERC20.transfer.selector
//         );
//         transferHookB.enableTransfer(
//             ARB_USDT, address(fundBChild1), address(fundB), IERC20.transfer.selector
//         );
//         transferHookB.enableTransfer(
//             ARB_USDC, address(fundBChild2), address(fundB), IERC20.transfer.selector
//         );
//         transferHookB.enableTransfer(
//             ARB_USDT, address(fundBChild2), address(fundB), IERC20.transfer.selector
//         );
//         transferHookB.enableTransfer(
//             ARB_USDC, address(fundBChild1), address(fundB), IERC20.transferFrom.selector
//         );
//         transferHookB.enableTransfer(
//             ARB_USDT, address(fundBChild1), address(fundB), IERC20.transferFrom.selector
//         );
//         transferHookB.enableTransfer(
//             ARB_USDC, address(fundBChild2), address(fundB), IERC20.transferFrom.selector
//         );
//         transferHookB.enableTransfer(
//             ARB_USDT, address(fundBChild2), address(fundB), IERC20.transferFrom.selector
//         );

//         vm.stopPrank();

//         assertTrue(
//             peripheryA.unitOfAccount().decimals() == peripheryB.unitOfAccount().decimals(),
//             "Unit of account decimals mismatch"
//         );
//         assertTrue(
//             peripheryA.unitOfAccount().decimals() == VALUATION_DECIMALS,
//             "Unit of account decimals mismatch"
//         );

//         vm.startPrank(broker);
//         USDC.approve(address(peripheryA), type(uint256).max);
//         USDT.approve(address(peripheryA), type(uint256).max);
//         USDC.approve(address(peripheryB), type(uint256).max);
//         USDT.approve(address(peripheryB), type(uint256).max);
//         vm.stopPrank();

//         assertTrue(
//             peripheryA.isBrokerAssetPolicyEnabled(brokerAId, ARB_USDC, true),
//             "USDC deposit policy not enabled for brokerAId on peripheryA"
//         );
//         assertTrue(
//             peripheryA.isBrokerAssetPolicyEnabled(brokerAId, ARB_USDC, false),
//             "USDC withdraw policy not enabled for brokerAId on peripheryA"
//         );
//         assertTrue(
//             peripheryA.isBrokerAssetPolicyEnabled(brokerAId, ARB_USDT, true),
//             "USDT deposit policy not enabled for brokerAId on peripheryA"
//         );

//         assertTrue(
//             peripheryB.isBrokerAssetPolicyEnabled(fundABrokerId, ARB_USDC, true),
//             "USDC deposit policy not enabled for fundABrokerId on peripheryB"
//         );
//         assertTrue(
//             peripheryB.isBrokerAssetPolicyEnabled(fundABrokerId, ARB_USDC, false),
//             "USDC withdraw policy not enabled for fundABrokerId on peripheryB"
//         );
//         assertTrue(
//             peripheryB.isBrokerAssetPolicyEnabled(fundABrokerId, ARB_USDT, true),
//             "USDT deposit policy not enabled for fundABrokerId on peripheryB"
//         );

//         // now configure the oracles
//         address unitOfAccountA = address(peripheryA.unitOfAccount());
//         vm.label(unitOfAccountA, "UnitOfAccount-A");
//         address unitOfAccountB = address(peripheryB.unitOfAccount());
//         vm.label(unitOfAccountB, "UnitOfAccount-B");

//         // setup USDC/USD oracle for FundA
//         ChainlinkOracle chainlinkOracle =
//             new ChainlinkOracle(ARB_USDC, unitOfAccountA, ARB_USDC_USD_FEED, 24 hours);
//         vm.label(address(chainlinkOracle), "ChainlinkOracle-USDC/USD");
//         vm.startPrank(protocolAdmin);
//         oracleRouter.govSetConfig(ARB_USDC, unitOfAccountA, address(chainlinkOracle));
//         vm.stopPrank();

//         // setup USDT/USD oracle for FundB
//         chainlinkOracle = new ChainlinkOracle(ARB_USDC, unitOfAccountB, ARB_USDC_USD_FEED, 24 hours);
//         vm.label(address(chainlinkOracle), "ChainlinkOracle-USDC/USD");
//         vm.startPrank(protocolAdmin);
//         oracleRouter.govSetConfig(ARB_USDC, unitOfAccountB, address(chainlinkOracle));
//         vm.stopPrank();

//         // setup USDT/USD oracle for FundA
//         chainlinkOracle = new ChainlinkOracle(ARB_USDT, unitOfAccountA, ARB_USDT_USD_FEED, 24 hours);
//         vm.label(address(chainlinkOracle), "ChainlinkOracle-USDT/USD");
//         vm.startPrank(protocolAdmin);
//         oracleRouter.govSetConfig(ARB_USDT, unitOfAccountA, address(chainlinkOracle));
//         vm.stopPrank();

//         // setup USDT/USD oracle for FundB
//         chainlinkOracle = new ChainlinkOracle(ARB_USDT, unitOfAccountB, ARB_USDT_USD_FEED, 24 hours);
//         vm.label(address(chainlinkOracle), "ChainlinkOracle-USDT/USD");
//         vm.startPrank(protocolAdmin);
//         oracleRouter.govSetConfig(ARB_USDT, unitOfAccountB, address(chainlinkOracle));
//         vm.stopPrank();

//         FixedRateOracle fixedRateOracle =
//             new FixedRateOracle(unitOfAccountA, unitOfAccountB, 1 * 10 ** VALUATION_DECIMALS);
//         vm.label(address(fixedRateOracle), "FixedRateOracle-A/B");
//         vm.startPrank(protocolAdmin);
//         oracleRouter.govSetConfig(unitOfAccountA, unitOfAccountB, address(fixedRateOracle));
//         vm.stopPrank();

//         // setup FundValuationOracle for FundA and FundB
//         vm.startPrank(protocolAdmin);
//         oracleRouter.govSetResolvedVault(address(peripheryB.internalVault()), true);
//         oracleRouter.govSetResolvedVault(address(peripheryA.internalVault()), true);
//         vm.stopPrank();
//     }
// }
