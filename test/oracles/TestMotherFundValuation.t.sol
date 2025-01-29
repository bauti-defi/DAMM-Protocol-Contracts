// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

// import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
// import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
// import {SafeL2} from "@safe-contracts/SafeL2.sol";
// import {FundCallbackHandler} from "@src/core/FundCallbackHandler.sol";
// import {MockERC20} from "@test/mocks/MockERC20.sol";
// import {TokenMinter} from "@test/forked/TokenMinter.sol";
// import {EulerRouter} from "@euler-price-oracle/EulerRouter.sol";
// import {ChainlinkOracle} from "@euler-price-oracle/adapter/chainlink/ChainlinkOracle.sol";
// import {FundValuationOracle} from "@src/oracles/FundValuationOracle.sol";
// import {
//     ARB_USDC_USD_FEED,
//     ARB_USDT_USD_FEED,
//     ARB_DAI_USD_FEED,
//     ARB_ETH_USD_FEED
// } from "@test/forked/ChainlinkOracleFeeds.sol";
// import {Periphery} from "@src/modules/deposit/Periphery.sol";
// import {AssetPolicy} from "@src/modules/deposit/Structs.sol";
// import {IFund} from "@src/interfaces/IFund.sol";
// import {FundFactory} from "@src/core/FundFactory.sol";
// import "@src/interfaces/IOwnable.sol";
// import "@src/libs/Constants.sol";
// import "@src/libs/Errors.sol";

// uint256 constant USD_DECIMALS = 8;

// /// Test that the mother fund valuation oracle works as expected
// /// the test will have one main fund (FundA) and one child fund (FundB)
// /// both the mother and child will have the same assets of interest
// contract TestMotherFundValuation is TestBaseProtocol, TestBaseGnosis, TokenMinter {
//     address internal protocolAdmin;
//     uint256 internal protocolAdminPK;

//     FundFactory internal fundFactory;

//     IFund internal fundA;
//     IFund internal fundB;

//     FundCallbackHandler internal callbackHandler;
//     EulerRouter internal oracleRouter;
//     Periphery internal periphery;
//     FundValuationOracle internal fundBValuationOracle;
//     FundValuationOracle internal fundAValuationOracle;
//     address internal unitOfAccount;

//     address positionOpenerCloser;

//     uint256 internal arbitrumFork;

//     function setUp() public override(TestBaseProtocol, TestBaseGnosis, TokenMinter) {
//         arbitrumFork = vm.createFork(vm.envString("ARBI_RPC_URL"));

//         vm.selectFork(arbitrumFork);
//         assertEq(vm.activeFork(), arbitrumFork);

//         vm.rollFork(218796378);

//         TestBaseProtocol.setUp();
//         TestBaseGnosis.setUp();
//         TokenMinter.setUp();

//         fundFactory = new FundFactory();
//         vm.label(address(fundFactory), "FundFactory");

//         positionOpenerCloser = makeAddr("PositionOpener");

//         (protocolAdmin, protocolAdminPK) = makeAddrAndKey("ProtocolAdmin");
//         vm.deal(protocolAdmin, 1000 ether);

//         address[] memory admins = new address[](1);
//         admins[0] = protocolAdmin;

//         fundA =
//             fundFactory.deployFund(address(safeProxyFactory), address(safeSingleton), admins, 1, 1);
//         vm.label(address(fundA), "FundA");

//         fundB =
//             fundFactory.deployFund(address(safeProxyFactory), address(safeSingleton), admins, 2, 1);
//         vm.label(address(fundB), "FundB");

//         vm.prank(protocolAdmin);
//         oracleRouter = new EulerRouter(address(1), address(protocolAdmin));
//         vm.label(address(oracleRouter), "OracleRouter");

//         // deploy periphery using module factory
//         periphery = Periphery(
//             deployModule(
//                 payable(address(fundA)),
//                 protocolAdmin,
//                 protocolAdminPK,
//                 bytes32("periphery"),
//                 0,
//                 abi.encodePacked(
//                     type(Periphery).creationCode,
//                     abi.encode(
//                         "TestVault",
//                         "TV",
//                         USD_DECIMALS, // must be same as underlying chainlink oracles. USD = 8
//                         payable(address(fundA)),
//                         address(oracleRouter),
//                         address(fundA),
//                         makeAddr("FeeRecipient"),
//                         /// accounts are not transferable
//                         false
//                     )
//                 )
//             )
//         );

//         assertTrue(fundA.isModuleEnabled(address(periphery)), "Periphery not module");

//         // set up position opener
//         addModuleWithRoles(
//             payable(address(fundA)),
//             protocolAdmin,
//             protocolAdminPK,
//             positionOpenerCloser,
//             POSITION_OPENER_ROLE | POSITION_CLOSER_ROLE
//         );

//         assertTrue(fundA.isModuleEnabled(positionOpenerCloser), "Position opener not module");
//         assertTrue(
//             fundA.hasAllRoles(positionOpenerCloser, POSITION_OPENER_ROLE),
//             "Position opener not authorized"
//         );

//         // lets enable assets on the fundA
//         // vm.startPrank(address(fundA));
//         // fundA.setAssetToValuate(ARB_USDC);
//         // fundA.setAssetToValuate(ARB_USDT);
//         // fundA.setAssetToValuate(ARB_DAI);
//         // fundA.setAssetToValuate(ARB_USDCe);

//         // // native eth
//         // fundA.setAssetToValuate(NATIVE_ASSET);
//         // vm.stopPrank();

//         // // now lets set fundB as child of fundA
//         // vm.prank(address(fundA));
//         // fundA.addChildFund(address(fundB));

//         // // now lets enable assets on the fundB
//         // vm.startPrank(address(fundB));
//         // fundB.setAssetToValuate(ARB_USDC);
//         // fundB.setAssetToValuate(ARB_USDT);
//         // fundB.setAssetToValuate(ARB_DAI);
//         // fundB.setAssetToValuate(ARB_USDCe);

//         // // native eth
//         // fundB.setAssetToValuate(NATIVE_ASSET);
//         // vm.stopPrank();

//         unitOfAccount = address(periphery.unitOfAccount());

//         address[] memory assetsToValuate = new address[](5);
//         assetsToValuate[0] = ARB_USDC;
//         assetsToValuate[1] = ARB_USDT;
//         assetsToValuate[2] = ARB_DAI;
//         assetsToValuate[3] = ARB_USDCe;
//         assetsToValuate[4] = NATIVE_ASSET;

//         fundAValuationOracle = new FundValuationOracle(address(oracleRouter), assetsToValuate);
//         vm.label(address(fundAValuationOracle), "FundValuationOracle-FundA");
//         vm.prank(protocolAdmin);
//         oracleRouter.govSetConfig(address(fundA), unitOfAccount, address(fundAValuationOracle));

//         fundBValuationOracle = new FundValuationOracle(address(oracleRouter), assetsToValuate);
//         vm.label(address(fundBValuationOracle), "FundValuationOracle-FundB");
//         vm.prank(protocolAdmin);
//         oracleRouter.govSetConfig(address(fundB), unitOfAccount, address(fundBValuationOracle));

//         // setup USDC/USD oracle for FundA
//         ChainlinkOracle chainlinkOracle =
//             new ChainlinkOracle(ARB_USDC, unitOfAccount, ARB_USDC_USD_FEED, 24 hours);
//         vm.label(address(chainlinkOracle), "ChainlinkOracle-USDC");
//         vm.prank(protocolAdmin);
//         oracleRouter.govSetConfig(ARB_USDC, unitOfAccount, address(chainlinkOracle));

//         // setup USDT/USD oracle for FundA
//         chainlinkOracle = new ChainlinkOracle(ARB_USDT, unitOfAccount, ARB_USDT_USD_FEED, 24 hours);
//         vm.label(address(chainlinkOracle), "ChainlinkOracle-USDT");
//         vm.prank(protocolAdmin);
//         oracleRouter.govSetConfig(ARB_USDT, unitOfAccount, address(chainlinkOracle));

//         // setup DAI/USD oracle for FundA
//         chainlinkOracle = new ChainlinkOracle(ARB_DAI, unitOfAccount, ARB_DAI_USD_FEED, 24 hours);
//         vm.label(address(chainlinkOracle), "ChainlinkOracle-DAI");
//         vm.prank(protocolAdmin);
//         oracleRouter.govSetConfig(ARB_DAI, unitOfAccount, address(chainlinkOracle));

//         // setup USDCe/USD oracle for FundA
//         chainlinkOracle = new ChainlinkOracle(ARB_USDCe, unitOfAccount, ARB_USDC_USD_FEED, 24 hours);
//         vm.label(address(chainlinkOracle), "ChainlinkOracle-USDCe");
//         vm.prank(protocolAdmin);
//         oracleRouter.govSetConfig(ARB_USDCe, unitOfAccount, address(chainlinkOracle));

//         // setup ETH/USD oracle for FundA
//         chainlinkOracle =
//             new ChainlinkOracle(NATIVE_ASSET, unitOfAccount, ARB_ETH_USD_FEED, 24 hours);
//         vm.label(address(chainlinkOracle), "ChainlinkOracle-ETH");
//         vm.prank(protocolAdmin);
//         oracleRouter.govSetConfig(NATIVE_ASSET, unitOfAccount, address(chainlinkOracle));
//     }

//     function test_cannot_valuate_fund_with_open_positions() public {
//         assertEq(
//             fundAValuationOracle.getQuote(0, address(fundA), unitOfAccount),
//             0,
//             "Total assets should be 0"
//         );
//         assertEq(
//             oracleRouter.getQuote(0, address(fundA), unitOfAccount), 0, "Total assets should be 0"
//         );
//         assertEq(fundA.hasOpenPositions(), false, "No open positions");

//         // the caller must be an active module
//         vm.prank(positionOpenerCloser);
//         assertTrue(fundA.onPositionOpened(bytes32(uint256(1))));

//         mintUSDC(address(fundA), 1000 * (10 ** 6));
//         mintUSDT(address(fundA), 1000 * (10 ** 6));
//         mintDAI(address(fundA), 1000 * (10 ** 18));
//         mintUSDCe(address(fundA), 1000 * (10 ** 6));

//         vm.expectRevert(Errors.FundValuationOracle_FundNotFullyDivested.selector);
//         fundAValuationOracle.getQuote(0, address(fundA), unitOfAccount);
//         vm.expectRevert(Errors.FundValuationOracle_FundNotFullyDivested.selector);
//         oracleRouter.getQuote(0, address(fundA), unitOfAccount);

//         assertEq(fundA.hasOpenPositions(), true, "No open positions");

//         // close the position
//         vm.prank(positionOpenerCloser);
//         assertTrue(fundA.onPositionClosed(bytes32(uint256(1))));

//         assertEq(fundA.hasOpenPositions(), false, "No open positions");
//         assertEq(fundA.getFundLiquidationTimeSeries().length, 1);
//         assertEq(fundA.getLatestLiquidationBlock(), int256(block.number));
//         assertTrue(
//             fundAValuationOracle.getQuote(0, address(fundA), unitOfAccount) > 0,
//             "Total assets of fund A should not be 0"
//         );
//         assertTrue(
//             oracleRouter.getQuote(0, address(fundA), unitOfAccount) > 0,
//             "Total assets of fund A should not be 0"
//         );
//     }

//     function test_valuate_fund_in_USD(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e)
//         public
//     {
//         vm.assume(a < 1e15 && a > 0);
//         vm.assume(b < 1e15 && b > 0);
//         vm.assume(c < 1e15 && c > 0);
//         vm.assume(d < 1e15 && d > 0);
//         vm.assume(e < 1e15 && e > 0);
//         assertEq(
//             fundAValuationOracle.getQuote(0, address(fundA), unitOfAccount),
//             0,
//             "Total assets of fund A should be 0"
//         );
//         assertEq(
//             oracleRouter.getQuote(0, address(fundA), unitOfAccount),
//             0,
//             "Total assets of fund A should be 0"
//         );
//         assertEq(
//             fundBValuationOracle.getQuote(0, address(fundB), unitOfAccount),
//             0,
//             "Total assets of fund B should be 0"
//         );
//         assertEq(
//             oracleRouter.getQuote(0, address(fundB), unitOfAccount),
//             0,
//             "Total assets of fund B should be 0"
//         );

//         // price at current block: 218796378
//         uint256 eth_usd_price = 384782218166;

//         // mint some USDC and USDT to fundA
//         mintUSDC(address(fundA), a * (10 ** 6));
//         mintUSDT(address(fundA), b * (10 ** 6));
//         mintDAI(address(fundA), c * (10 ** 18));
//         mintUSDCe(address(fundA), d * (10 ** 6));
//         deal(address(fundA), e);

//         // mint some USDC and USDT to fundB
//         mintUSDC(address(fundB), a * (10 ** 6));
//         mintUSDT(address(fundB), b * (10 ** 6));
//         mintDAI(address(fundB), c * (10 ** 18));
//         mintUSDCe(address(fundB), d * (10 ** 6));
//         deal(address(fundB), e);

//         uint256 finalAmount = (a + b + c + d) * (10 ** USD_DECIMALS) + e * eth_usd_price / 1 ether;

//         // total assets in USD
//         assertApproxEqRel(
//             fundAValuationOracle.getQuote(0, address(fundA), unitOfAccount),
//             2 * finalAmount,
//             0.1e18,
//             "Total assets of fund A should be about same in USD"
//         );
//         assertApproxEqRel(
//             oracleRouter.getQuote(0, address(fundA), unitOfAccount),
//             2 * finalAmount,
//             0.1e18,
//             "Total assets of fund A should be about same in USD"
//         );
//         assertApproxEqRel(
//             fundBValuationOracle.getQuote(0, address(fundB), unitOfAccount),
//             finalAmount,
//             0.1e18,
//             "Total assets of fund B should be about same in USD"
//         );
//         assertApproxEqRel(
//             oracleRouter.getQuote(0, address(fundB), unitOfAccount),
//             finalAmount,
//             0.1e18,
//             "Total assets of fund B should be about same in USD"
//         );
//     }

//     function test_fund_valuation_not_supported() public {
//         vm.expectRevert();
//         oracleRouter.getQuote(100, unitOfAccount, address(fundA));
//     }

//     function test_fund_liquidation_time_series() public {
//         assertEq(fundA.getFundLiquidationTimeSeries().length, 0);
//         assertEq(fundA.getLatestLiquidationBlock(), -1);

//         // the caller must be an active module
//         vm.prank(positionOpenerCloser);
//         assertTrue(fundA.onPositionOpened(bytes32(uint256(1))));

//         assertEq(fundA.getFundLiquidationTimeSeries().length, 0);
//         assertEq(fundA.getLatestLiquidationBlock(), -1);
//         assertEq(fundA.hasOpenPositions(), true, "No open positions");

//         // close the position
//         vm.prank(positionOpenerCloser);
//         assertTrue(fundA.onPositionClosed(bytes32(uint256(1))));

//         assertEq(fundA.hasOpenPositions(), false, "No open positions");
//         assertEq(fundA.getFundLiquidationTimeSeries().length, 1);
//         assertEq(fundA.getLatestLiquidationBlock(), int256(block.number));

//         // close the position that was already closed
//         vm.prank(positionOpenerCloser);
//         assertFalse(fundA.onPositionClosed(bytes32(uint256(1))));

//         assertEq(fundA.hasOpenPositions(), false, "No open positions");
//         assertEq(fundA.getFundLiquidationTimeSeries().length, 1);
//         assertEq(fundA.getLatestLiquidationBlock(), int256(block.number));
//     }
// }
