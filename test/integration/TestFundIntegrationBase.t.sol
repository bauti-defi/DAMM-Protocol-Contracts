// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import {Test} from "forge-std/Test.sol";
// import {console2} from "forge-std/console2.sol";
// import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
// import {EulerRouter} from "@euler-price-oracle/EulerRouter.sol";
// import {FixedRateOracle} from "@euler-price-oracle/adapter/fixed/FixedRateOracle.sol";
// import {Periphery} from "@src/modules/deposit/Periphery.sol";
// import {IPeriphery} from "@src/interfaces/IPeriphery.sol";
// import {Enum} from "@safe-contracts/common/Enum.sol";
// import "@src/modules/deposit/Structs.sol";
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
// import {ISafe} from "@src/interfaces/ISafe.sol";
// import {ModuleProxyFactory} from "@zodiac/factory/ModuleProxyFactory.sol";

// abstract contract TestFundIntegrationBase is TestBaseGnosis, TokenMinter {
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

//     ModuleProxyFactory internal moduleProxyFactory;

//     ISafe internal fundA;
//     ISafe internal fundB;
//     ISafe internal fundAChild1;
//     ISafe internal fundAChild2;
//     ISafe internal fundBChild1;
//     ISafe internal fundBChild2;

//     address internal peripheryMastercopy;

//     Periphery internal p_fundA;
//     Periphery internal p_fundB;
//     Periphery internal p_fundAChild1;
//     Periphery internal p_fundAChild2;
//     Periphery internal p_fundBChild1;
//     Periphery internal p_fundBChild2;

//     EulerRouter internal oracleRouter;

//     uint256 internal brokerAId;
//     uint256 internal brokerBId;
//     uint256 internal fundABrokerId;

//     uint256 internal nonce;

//     function setUp() public virtual override(TestBaseGnosis, TokenMinter) {
//         _setupFork();
//         _setupBase();
//         _deployFunds();
//         _deployInfrastructure();
//        _configureFunds();
//     }

//     function _setupFork() internal {
//         arbitrumFork = vm.createFork(vm.envString("ARBI_RPC_URL"));
//         vm.selectFork(arbitrumFork);
//         assertEq(vm.activeFork(), arbitrumFork);
//         vm.rollFork(218796378);
//     }

//     function _setupBase() internal {
//         TestBaseGnosis.setUp();
//         TokenMinter.setUp();

//         feeRecipient = makeAddr("FeeRecipient");
//         operator = makeAddr("Operator");
//         broker = makeAddr("Broker");
//         (protocolAdmin, protocolAdminPK) = makeAddrAndKey("ProtocolAdmin");

//         moduleProxyFactory = new ModuleProxyFactory();

//         peripheryMastercopy = address(new Periphery());
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
//     }

//     function _deployOracleRouter() internal {
//         vm.prank(protocolAdmin);
//         oracleRouter = new EulerRouter(address(1), address(protocolAdmin));
//         vm.label(address(oracleRouter), "OracleRouter");
//     }

//     function _deployPeriphery() internal {
//         // Deploy periphery A
//         bytes memory initializeParams = abi.encodeWithSelector(Periphery.setUp.selector, abi.encode(
//                         "PeripheryA",
//                         "PA1",
//                         VALUATION_DECIMALS,
//                         payable(address(fundA)),
//                         address(oracleRouter),
//                         address(fundA),
//                         feeRecipient
//                     ));
//         p_fundA = Periphery(moduleProxyFactory.deployModule(peripheryMastercopy, initializeParams, uint256(bytes32("p_fundA"))));
//         vm.prank(address(fundA));
//         fundA.enableModule(address(p_fundA));
//         vm.label(address(p_fundA), "PeripheryA");
//         assertTrue(fundA.isModuleEnabled(address(p_fundA)), "PeripheryA is not module");

//         // Deploy periphery B
//         initializeParams = abi.encodeWithSelector(Periphery.setUp.selector, abi.encode(
//                         "PeripheryB",
//                         "PB1",
//                         VALUATION_DECIMALS,
//                         payable(address(fundB)),
//                         address(oracleRouter),
//                         address(fundB),
//                         feeRecipient
//                     ));
//         p_fundB = Periphery(moduleProxyFactory.deployModule(peripheryMastercopy, initializeParams, uint256(bytes32("p_fundB"))));
//         vm.prank(address(fundB));
//         fundB.enableModule(address(p_fundB));
//         vm.label(address(p_fundB), "PeripheryB");
//         assertTrue(fundB.isModuleEnabled(address(p_fundB)), "PeripheryB is not module");

//         // Deploy periphery A child 1
//         initializeParams = abi.encodeWithSelector(Periphery.setUp.selector, abi.encode(
//                         "PeripheryAChild1",
//                         "PAC1",
//                         VALUATION_DECIMALS,
//                         payable(address(fundAChild1)),
//                         address(oracleRouter),
//                         address(fundAChild1),
//                         feeRecipient
//                     ));
//         p_fundAChild1 = Periphery(moduleProxyFactory.deployModule(peripheryMastercopy, initializeParams, uint256(bytes32("peripheryAChild1"))));
//         vm.prank(address(fundAChild1));
//         fundAChild1.enableModule(address(p_fundAChild1));
//         vm.label(address(p_fundAChild1), "PeripheryAChild1");
//         assertTrue(fundAChild1.isModuleEnabled(address(p_fundAChild1)), "PeripheryAChild1 is not module");

//         // Deploy periphery A child 2
//         initializeParams = abi.encodeWithSelector(Periphery.setUp.selector, abi.encode(
//                         "PeripheryAChild2",
//                         "PAC2",
//                         VALUATION_DECIMALS,
//                         payable(address(fundAChild2)),
//                         address(oracleRouter),
//                         address(fundAChild2),
//                         feeRecipient
//                     ));
//         p_fundAChild2 = Periphery(moduleProxyFactory.deployModule(peripheryMastercopy, initializeParams, uint256(bytes32("peripheryAChild2"))));
//         vm.prank(address(fundAChild2));
//         fundAChild2.enableModule(address(p_fundAChild2));
//         vm.label(address(p_fundAChild2), "PeripheryAChild2");
//         assertTrue(fundAChild2.isModuleEnabled(address(p_fundAChild2)), "PeripheryAChild2 is not module");

//         // Deploy periphery B child 1
//         initializeParams = abi.encodeWithSelector(Periphery.setUp.selector, abi.encode(
//                         "PeripheryBChild1",
//                         "PBC1",
//                         VALUATION_DECIMALS,
//                         payable(address(fundBChild1)),
//                         address(oracleRouter),
//                         address(fundBChild1),
//                         feeRecipient
//                     ));
//         p_fundBChild1 = Periphery(moduleProxyFactory.deployModule(peripheryMastercopy, initializeParams, uint256(bytes32("peripheryBChild1"))));
//         vm.prank(address(fundBChild1));
//         fundBChild1.enableModule(address(p_fundBChild1));
//         vm.label(address(p_fundBChild1), "PeripheryBChild1");
//         assertTrue(fundBChild1.isModuleEnabled(address(p_fundBChild1)), "PeripheryBChild1 is not module");

//         // Deploy periphery B child 2
//         initializeParams = abi.encodeWithSelector(Periphery.setUp.selector, abi.encode(
//                         "PeripheryBChild2",
//                         "PBC2",
//                         VALUATION_DECIMALS,
//                         payable(address(fundBChild2)),
//                         address(oracleRouter),
//                         address(fundBChild2),
//                         feeRecipient
//                     ));
//         p_fundBChild2 = Periphery(moduleProxyFactory.deployModule(peripheryMastercopy, initializeParams, uint256(bytes32("peripheryBChild2"))));
//         vm.prank(address(fundBChild2));
//         fundBChild2.enableModule(address(p_fundBChild2));
//         vm.label(address(p_fundBChild2), "PeripheryBChild2");
//         assertTrue(fundBChild2.isModuleEnabled(address(p_fundBChild2)), "PeripheryBChild2 is not module");
//     }

//     function _enableAssetPolicy(address fund, address periphery, address asset, bool canDeposit, bool canWithdraw) internal {
//         vm.startPrank(address(fund));
//         periphery.enableGlobalAssetPolicy(asset, AssetPolicy({
//             minimumDeposit: 100,
//             minimumWithdrawal: 100,
//             canDeposit: canDeposit,
//             canWithdraw: canWithdraw,
//             enabled: true
//         }));
//         vm.stopPrank();
//     }

//     function _mintBrokerNFT(address fund, address periphery, address broker) internal returns (uint256 brokerId) {
//         vm.startPrank(address(fund));
//         brokerId = periphery.openAccount(CreateAccountParams({
//             user: broker,
//             brokerPerformanceFeeInBps: 0,
//             protocolPerformanceFeeInBps: 0,
//             brokerEntranceFeeInBps: 0,
//             protocolEntranceFeeInBps: 0,
//             brokerExitFeeInBps: 0,
//             protocolExitFeeInBps: 0,
//             transferable: false,
//             ttl: 365 days,
//             shareMintLimit: type(uint256).max,
//             feeRecipient: address(0)
//         }));
//         vm.stopPrank();
//     }

//     function _enableAssetForBroker(address fund, address periphery, address broker, address asset, bool canDeposit, bool canWithdraw) internal {
//         vm.startPrank(address(fund));
//         if(canDeposit) periphery.enableBrokerAssetPolicy(broker, asset, true);
//         if(canWithdraw) periphery.enableBrokerAssetPolicy(broker, asset, false);
//         vm.stopPrank();
//     }

//     function _configureFunds() internal {
//         _enableAssetPolicy(fundA, p_fundA, ARB_USDC, true, true);
//         _enableAssetPolicy(fundA, p_fundA, ARB_USDT, true, true);
//         brokerAId = _mintBrokerNFT(fundA, p_fundA, broker);

//         _enableAssetForBroker(fundA, p_fundA, broker, ARB_USDC, true, true);
//         _enableAssetForBroker(fundA, p_fundA, broker, ARB_USDT, true, false);

//         // give periphery B allowance to deposit funds from Fund A
//         vm.startPrank(address(fundA));
//         USDC.approve(address(p_fundB), type(uint256).max);
//         USDT.approve(address(p_fundB), type(uint256).max);
//         p_fundB.internalVault().approve(address(p_fundB), type(uint256).max);
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
//         fundABrokerId = p_fundB.openAccount(
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

//         assertTrue(p_fundB.balanceOf(address(fundA)) > 0, "Fund A broker NFT not minted");
//         assertTrue(
//             p_fundB.ownerOf(fundABrokerId) == address(fundA), "Fund A broker NFT not minted"
//         );

//         // configure child funds for Fund B
//         vm.startPrank(address(fundB));

//         // open broker account for Fund B
//         brokerBId = p_fundB.openAccount(
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
//         p_fundB.enableGlobalAssetPolicy(
//             ARB_USDC,
//             AssetPolicy({
//                 minimumDeposit: 100,
//                 minimumWithdrawal: 100,
//                 canDeposit: true,
//                 canWithdraw: true,
//                 enabled: true
//             })
//         );
//         p_fundB.enableGlobalAssetPolicy(
//             ARB_USDT,
//             AssetPolicy({
//                 minimumDeposit: 100,
//                 minimumWithdrawal: 100,
//                 canDeposit: true,
//                 canWithdraw: false,
//                 enabled: true
//             })
//         );

//         p_fundB.enableBrokerAssetPolicy(fundABrokerId, ARB_USDC, true);
//         p_fundB.enableBrokerAssetPolicy(fundABrokerId, ARB_USDC, false);
//         p_fundB.enableBrokerAssetPolicy(fundABrokerId, ARB_USDT, true);

//         vm.stopPrank();

//         assertTrue(
//             p_fundA.unitOfAccount().decimals() == p_fundB.unitOfAccount().decimals(),
//             "Unit of account decimals mismatch"
//         );
//         assertTrue(
//             p_fundA.unitOfAccount().decimals() == VALUATION_DECIMALS,
//             "Unit of account decimals mismatch"
//         );

//         vm.startPrank(broker);
//         USDC.approve(address(p_fundA), type(uint256).max);
//         USDT.approve(address(p_fundA), type(uint256).max);
//         USDC.approve(address(p_fundB), type(uint256).max);
//         USDT.approve(address(p_fundB), type(uint256).max);
//         vm.stopPrank();

//         assertTrue(
//             p_fundA.isBrokerAssetPolicyEnabled(brokerAId, ARB_USDC, true),
//             "USDC deposit policy not enabled for brokerAId on p_fundA"
//         );
//         assertTrue(
//             p_fundA.isBrokerAssetPolicyEnabled(brokerAId, ARB_USDC, false),
//             "USDC withdraw policy not enabled for brokerAId on p_fundA"
//         );
//         assertTrue(
//             p_fundA.isBrokerAssetPolicyEnabled(brokerAId, ARB_USDT, true),
//             "USDT deposit policy not enabled for brokerAId on p_fundA"
//         );

//         assertTrue(
//             p_fundB.isBrokerAssetPolicyEnabled(fundABrokerId, ARB_USDC, true),
//             "USDC deposit policy not enabled for fundABrokerId on p_fundB"
//         );
//         assertTrue(
//             p_fundB.isBrokerAssetPolicyEnabled(fundABrokerId, ARB_USDC, false),
//             "USDC withdraw policy not enabled for fundABrokerId on p_fundB"
//         );
//         assertTrue(
//             p_fundB.isBrokerAssetPolicyEnabled(fundABrokerId, ARB_USDT, true),
//             "USDT deposit policy not enabled for fundABrokerId on p_fundB"
//         );

//         // now configure the oracles
//         address unitOfAccountA = address(p_fundA.unitOfAccount());
//         vm.label(unitOfAccountA, "UnitOfAccount-A");
//         address unitOfAccountB = address(p_fundB.unitOfAccount());
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
//         oracleRouter.govSetResolvedVault(address(p_fundB.internalVault()), true);
//         oracleRouter.govSetResolvedVault(address(p_fundA.internalVault()), true);
//         vm.stopPrank();
//     }
// }
