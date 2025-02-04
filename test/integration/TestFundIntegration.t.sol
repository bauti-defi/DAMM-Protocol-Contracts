// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "./TestFundIntegrationBase.t.sol";
// import {BalanceOfOracle} from "@src/oracles/BalanceOfOracle.sol";
// import {TrustedRateOracle} from "@src/oracles/TrustedRateOracle.sol";

// /// This contract will test a full deployment of 2 funds with child funds included.
// /// Fund A (mother) will have two child funds. Fund B (mother) will have 2 childs funds.
// /// Fund A will have deposits in fund B. Fund B will not be aware of Fund A.
// /// The goal of this integration test is to validate that funds can correctly integrate with each other
// /// and that valuation of fund assets works correctly.
// /// No strategies will be deployed in this test => no protocols will be integrated.
// /// The only hooks to use are the vault connector for deposits and withdrawals of Fund A to Fund B.
// /// And the transfer hook for transfering assets to and from child funds.
// contract TestFundIntegration is TestFundIntegrationBase {
//     BalanceOfOracle internal fundABalanceOfOracle;
//     BalanceOfOracle internal fundBBalanceOfOracle;

//     TrustedRateOracle internal fundATrustedRateOracle;
//     TrustedRateOracle internal fundBTrustedRateOracle;

//     function _setUpBalanceOfOracles() internal {
//         // now configure the oracles
//         address unitOfAccountA = address(p_fundA.unitOfAccount());
//         vm.label(unitOfAccountA, "UnitOfAccount-A");
//         address unitOfAccountB = address(p_fundB.unitOfAccount());
//         vm.label(unitOfAccountB, "UnitOfAccount-B");

//         fundABalanceOfOracle = new BalanceOfOracle(protocolAdmin, address(oracleRouter));
//         vm.label(address(fundABalanceOfOracle), "BalanceOfOracle-FundA");
//         vm.startPrank(protocolAdmin);
//         fundABalanceOfOracle.addBalanceToValuate(ARB_USDC, address(fundA));
//         fundABalanceOfOracle.addBalanceToValuate(ARB_USDC, address(fundAChild1));
//         fundABalanceOfOracle.addBalanceToValuate(ARB_USDC, address(fundAChild2));
//         fundABalanceOfOracle.addBalanceToValuate(ARB_USDT, address(fundA));
//         fundABalanceOfOracle.addBalanceToValuate(ARB_USDT, address(fundAChild1));
//         fundABalanceOfOracle.addBalanceToValuate(ARB_USDT, address(fundAChild2));
//         fundABalanceOfOracle.addBalanceToValuate(
//             address(p_fundB.internalVault()), address(fundA)
//         );

//         oracleRouter.govSetConfig(address(fundA), unitOfAccountA, address(fundABalanceOfOracle));
//         vm.stopPrank();

//         // setup BalanceOf for all child funds
//         fundBBalanceOfOracle = new BalanceOfOracle(protocolAdmin, address(oracleRouter));
//         vm.label(address(fundBBalanceOfOracle), "BalanceOfOracle-FundB");
//         vm.startPrank(protocolAdmin);
//         fundBBalanceOfOracle.addBalanceToValuate(ARB_USDC, address(fundB));
//         fundBBalanceOfOracle.addBalanceToValuate(ARB_USDC, address(fundBChild1));
//         fundBBalanceOfOracle.addBalanceToValuate(ARB_USDC, address(fundBChild2));
//         fundBBalanceOfOracle.addBalanceToValuate(ARB_USDT, address(fundB));
//         fundBBalanceOfOracle.addBalanceToValuate(ARB_USDT, address(fundBChild1));
//         fundBBalanceOfOracle.addBalanceToValuate(ARB_USDT, address(fundBChild2));

//         oracleRouter.govSetConfig(address(fundB), unitOfAccountB, address(fundBBalanceOfOracle));
//         vm.stopPrank();
//     }

//     function _setUpTrustedRateOracle() internal {
//         // now configure the oracles
//         address unitOfAccountA = address(p_fundA.unitOfAccount());
//         vm.label(unitOfAccountA, "UnitOfAccount-A");
//         address unitOfAccountB = address(p_fundB.unitOfAccount());
//         vm.label(unitOfAccountB, "UnitOfAccount-B");

//         // setup TrustedRateOracle for FundA
//         fundATrustedRateOracle =
//             new TrustedRateOracle(protocolAdmin, address(fundA), unitOfAccountA);
//         vm.label(address(fundATrustedRateOracle), "TrustedRateOracle-A");
//         vm.startPrank(protocolAdmin);
//         oracleRouter.govSetConfig(address(fundA), unitOfAccountA, address(fundATrustedRateOracle));
//         vm.stopPrank();

//         // setup TrustedRateOracle for FundB
//         fundBTrustedRateOracle =
//             new TrustedRateOracle(protocolAdmin, address(fundB), unitOfAccountB);
//         vm.label(address(fundBTrustedRateOracle), "TrustedRateOracle-B");
//         vm.startPrank(protocolAdmin);
//         oracleRouter.govSetConfig(address(fundB), unitOfAccountB, address(fundBTrustedRateOracle));
//         vm.stopPrank();
//     }

//     function test_valuation_with_trusted_rate_oracle() public {
//         _setUpTrustedRateOracle();

//         vm.startPrank(protocolAdmin);
//         fundATrustedRateOracle.updateRate(
//             1 * 10 ** (TRUSTED_ORACLE_PRECISION), block.timestamp + 100000
//         );
//         fundBTrustedRateOracle.updateRate(
//             1 * 10 ** (TRUSTED_ORACLE_PRECISION), block.timestamp + 100000
//         );
//         vm.stopPrank();

//         mintUSDC(broker, 100 * SCALAR);
//         mintUSDT(broker, 100 * SCALAR);

//         vm.startPrank(broker);
//         p_fundA.deposit(
//             DepositOrder({
//                 accountId: brokerAId,
//                 recipient: broker,
//                 asset: ARB_USDC,
//                 amount: 20 * SCALAR,
//                 deadline: block.timestamp + 1000,
//                 minSharesOut: 0,
//                 referralCode: 0
//             })
//         );
//         vm.stopPrank();

//         assertEq(USDC.balanceOf(broker), 80 * SCALAR);
//         assertEq(USDC.balanceOf(address(fundA)), 20 * SCALAR);
//         assertGt(p_fundA.internalVault().balanceOf(broker), 0);

//         // we check the fund A tvl using the oracle router
//         uint256 fundATvl = oracleRouter.getQuote(
//             p_fundA.internalVault().totalSupply(),
//             address(fundA),
//             address(p_fundA.unitOfAccount())
//         );
//         uint256 totalAssets = p_fundA.internalVault().totalAssets();
//         uint256 totalSupply = p_fundA.internalVault().totalSupply();

//         assertEq(fundATvl, totalAssets);
//         assertEq(p_fundA.internalVault().balanceOf(broker), totalSupply);

//         // now we transfer half of the USDC from Fund A to its children
//         // operator will do this through transaction module
//         // Transaction[] memory transactions = new Transaction[](2);

//         // transactions[0] = Transaction({
//         //     target: ARB_USDC,
//         //     value: 0,
//         //     targetSelector: IERC20.transfer.selector,
//         //     data: abi.encode(address(fundAChild1), 5 * SCALAR),
//         //     operation: uint8(Enum.Operation.Call)
//         // });

//         // transactions[1] = Transaction({
//         //     target: ARB_USDC,
//         //     value: 0,
//         //     targetSelector: IERC20.transfer.selector,
//         //     data: abi.encode(address(fundAChild2), 5 * SCALAR),
//         //     operation: uint8(Enum.Operation.Call)
//         // });

//         vm.startPrank(operator);
//         p_fundAChild1.deposit(DepositOrder({
//             accountId: brokerAId,
//             recipient: broker,
//             asset: ARB_USDC,
//             amount: 5 * SCALAR,
//             deadline: block.timestamp + 100000,
//             minSharesOut: 0,
//             referralCode: 0
//         }));
//         vm.stopPrank();

//     //     assertEq(USDC.balanceOf(address(fundAChild1)), 5 * SCALAR);
//     //     assertEq(USDC.balanceOf(address(fundAChild2)), 5 * SCALAR);
//     //     assertEq(USDC.balanceOf(address(fundA)), 10 * SCALAR);
//     //     assertEq(
//     //         oracleRouter.getQuote(
//     //             p_fundA.internalVault().totalSupply(),
//     //             address(fundA),
//     //             address(p_fundA.unitOfAccount())
//     //         ),
//     //         fundATvl
//     //     );

//     //     // now we deposit from Fund A to Fund B
//     //     // we will use the transaction module to do this
//     //     transactions = new Transaction[](1);

//     //     transactions[0] = Transaction({
//     //         target: address(p_fundB),
//     //         value: 0,
//     //         targetSelector: IPeriphery.deposit.selector,
//     //         data: abi.encode(
//     //             DepositOrder({
//     //                 accountId: fundABrokerId,
//     //                 recipient: address(fundA),
//     //                 asset: ARB_USDC,
//     //                 amount: 5 * SCALAR,
//     //                 deadline: block.timestamp + 100000,
//     //                 minSharesOut: 0,
//     //                 referralCode: 0
//     //             })
//     //         ),
//     //         operation: uint8(Enum.Operation.Call)
//     //     });

//     //     vm.prank(operator);
//     //     transactionModuleA.execute(transactions);

//     //     assertEq(USDC.balanceOf(address(fundAChild1)), 5 * SCALAR);
//     //     assertEq(USDC.balanceOf(address(fundAChild2)), 5 * SCALAR);
//     //     assertEq(USDC.balanceOf(address(fundA)), 5 * SCALAR);
//     //     assertEq(USDC.balanceOf(address(fundB)), 5 * SCALAR);
//     //     assertEq(
//     //         oracleRouter.getQuote(
//     //             p_fundA.internalVault().totalSupply(),
//     //             address(fundA),
//     //             address(p_fundA.unitOfAccount())
//     //         ),
//     //         fundATvl
//     //     );

//     //     // transfer from FundAChild1 to FundA
//     //     transactions = new Transaction[](2);

//     //     transactions[0] = Transaction({
//     //         target: ARB_USDC,
//     //         value: 0,
//     //         targetSelector: IERC20.transferFrom.selector,
//     //         data: abi.encode(address(fundAChild1), address(fundA), 5 * SCALAR),
//     //         operation: uint8(Enum.Operation.Call)
//     //     });

//     //     transactions[1] = Transaction({
//     //         target: ARB_USDC,
//     //         value: 0,
//     //         targetSelector: IERC20.transferFrom.selector,
//     //         data: abi.encode(address(fundAChild2), address(fundA), 5 * SCALAR),
//     //         operation: uint8(Enum.Operation.Call)
//     //     });

//     //     vm.prank(operator);
//     //     transactionModuleA.execute(transactions);

//     //     assertEq(USDC.balanceOf(address(fundAChild1)), 0);
//     //     assertEq(USDC.balanceOf(address(fundAChild2)), 0);
//     //     assertEq(USDC.balanceOf(address(fundA)), 15 * SCALAR);
//     //     assertEq(USDC.balanceOf(address(fundB)), 5 * SCALAR);
//     //     assertEq(
//     //         oracleRouter.getQuote(
//     //             p_fundA.internalVault().totalSupply(),
//     //             address(fundA),
//     //             address(p_fundA.unitOfAccount())
//     //         ),
//     //         fundATvl
//     //     );

//     //     // now we withdraw from FundB to FundA
//     //     transactions = new Transaction[](1);

//     //     transactions[0] = Transaction({
//     //         target: address(p_fundB),
//     //         value: 0,
//     //         targetSelector: IPeriphery.withdraw.selector,
//     //         data: abi.encode(
//     //             WithdrawOrder({
//     //                 accountId: fundABrokerId,
//     //                 to: address(fundA),
//     //                 asset: ARB_USDC,
//     //                 shares: type(uint256).max,
//     //                 deadline: block.timestamp + 100000,
//     //                 minAmountOut: 0,
//     //                 referralCode: 0
//     //             })
//     //         ),
//     //         operation: uint8(Enum.Operation.Call)
//     //     });

//     //     vm.prank(operator);
//     //     transactionModuleA.execute(transactions);

//     //     assertEq(USDC.balanceOf(address(fundAChild1)), 0);
//     //     assertEq(USDC.balanceOf(address(fundAChild2)), 0);
//     //     assertEq(USDC.balanceOf(address(fundA)), 20 * SCALAR);
//     //     assertEq(USDC.balanceOf(address(fundB)), 0);
//     //     assertEq(
//     //         oracleRouter.getQuote(
//     //             p_fundA.internalVault().totalSupply(),
//     //             address(fundA),
//     //             address(p_fundA.unitOfAccount())
//     //         ),
//     //         fundATvl
//     //     );
//     // }

//     // function test_valuation_with_balance_of_oracle() public {
//     //     _setUpBalanceOfOracles();

//     //     mintUSDC(broker, 10_000_000);
//     //     mintUSDT(broker, 10_000_000);

//     //     vm.startPrank(broker);
//     //     p_fundA.deposit(
//     //         DepositOrder({
//     //             accountId: brokerAId,
//     //             recipient: broker,
//     //             asset: ARB_USDC,
//     //             amount: 2_000_000,
//     //             deadline: block.timestamp + 1000,
//     //             minSharesOut: 0,
//     //             referralCode: 0
//     //         })
//     //     );
//     //     vm.stopPrank();

//     //     assertEq(USDC.balanceOf(broker), 8_000_000);
//     //     assertEq(USDC.balanceOf(address(fundA)), 2_000_000);
//     //     assertGt(p_fundA.internalVault().balanceOf(broker), 0);

//     //     // we check the fund A tvl using the oracle router
//     //     uint256 fundATvl =
//     //         oracleRouter.getQuote(0, address(fundA), address(p_fundA.unitOfAccount()));
//     //     uint256 totalAssets = p_fundA.internalVault().totalAssets();
//     //     uint256 totalSupply = p_fundA.internalVault().totalSupply();

//     //     assertEq(fundATvl, totalAssets);
//     //     assertEq(p_fundA.internalVault().balanceOf(broker), totalSupply);

//     //     // now we transfer half of the USDC from Fund A to its children
//     //     // operator will do this through transaction module
//     //     Transaction[] memory transactions = new Transaction[](2);

//     //     transactions[0] = Transaction({
//     //         target: ARB_USDC,
//     //         value: 0,
//     //         targetSelector: IERC20.transfer.selector,
//     //         data: abi.encode(address(fundAChild1), 500_000),
//     //         operation: uint8(Enum.Operation.Call)
//     //     });

//     //     transactions[1] = Transaction({
//     //         target: ARB_USDC,
//     //         value: 0,
//     //         targetSelector: IERC20.transfer.selector,
//     //         data: abi.encode(address(fundAChild2), 500_000),
//     //         operation: uint8(Enum.Operation.Call)
//     //     });

//     //     vm.prank(operator);
//     //     transactionModuleA.execute(transactions);

//     //     assertEq(USDC.balanceOf(address(fundAChild1)), 500_000);
//     //     assertEq(USDC.balanceOf(address(fundAChild2)), 500_000);
//     //     assertEq(USDC.balanceOf(address(fundA)), 1_000_000);
//     //     assertEq(
//     //         oracleRouter.getQuote(0, address(fundA), address(p_fundA.unitOfAccount())), fundATvl
//     //     );

//     //     // now we deposit from Fund A to Fund B
//     //     // we will use the transaction module to do this
//     //     transactions = new Transaction[](1);

//     //     transactions[0] = Transaction({
//     //         target: address(p_fundB),
//     //         value: 0,
//     //         targetSelector: IPeriphery.deposit.selector,
//     //         data: abi.encode(
//     //             DepositOrder({
//     //                 accountId: fundABrokerId,
//     //                 recipient: address(fundA),
//     //                 asset: ARB_USDC,
//     //                 amount: 500_000,
//     //                 deadline: block.timestamp + 100000,
//     //                 minSharesOut: 0,
//     //                 referralCode: 0
//     //             })
//     //         ),
//     //         operation: uint8(Enum.Operation.Call)
//     //     });

//     //     vm.prank(operator);
//     //     transactionModuleA.execute(transactions);

//     //     assertEq(USDC.balanceOf(address(fundAChild1)), 500_000);
//     //     assertEq(USDC.balanceOf(address(fundAChild2)), 500_000);
//     //     assertEq(USDC.balanceOf(address(fundA)), 500_000);
//     //     assertEq(USDC.balanceOf(address(fundB)), 500_000);
//     //     assertEq(
//     //         oracleRouter.getQuote(0, address(fundA), address(p_fundA.unitOfAccount())), fundATvl
//     //     );

//     //     // transfer from FundAChild1 to FundA
//     //     transactions = new Transaction[](2);

//     //     transactions[0] = Transaction({
//     //         target: ARB_USDC,
//     //         value: 0,
//     //         targetSelector: IERC20.transferFrom.selector,
//     //         data: abi.encode(address(fundAChild1), address(fundA), 500_000),
//     //         operation: uint8(Enum.Operation.Call)
//     //     });

//     //     transactions[1] = Transaction({
//     //         target: ARB_USDC,
//     //         value: 0,
//     //         targetSelector: IERC20.transferFrom.selector,
//     //         data: abi.encode(address(fundAChild2), address(fundA), 500_000),
//     //         operation: uint8(Enum.Operation.Call)
//     //     });

//     //     vm.prank(operator);
//     //     transactionModuleA.execute(transactions);

//     //     assertEq(USDC.balanceOf(address(fundAChild1)), 0);
//     //     assertEq(USDC.balanceOf(address(fundAChild2)), 0);
//     //     assertEq(USDC.balanceOf(address(fundA)), 1_500_000);
//     //     assertEq(USDC.balanceOf(address(fundB)), 500_000);
//     //     assertEq(
//     //         oracleRouter.getQuote(0, address(fundA), address(p_fundA.unitOfAccount())), fundATvl
//     //     );

//     //     // now we withdraw from FundB to FundA
//     //     transactions = new Transaction[](1);

//     //     transactions[0] = Transaction({
//     //         target: address(p_fundB),
//     //         value: 0,
//     //         targetSelector: IPeriphery.withdraw.selector,
//     //         data: abi.encode(
//     //             WithdrawOrder({
//     //                 accountId: fundABrokerId,
//     //                 to: address(fundA),
//     //                 asset: ARB_USDC,
//     //                 shares: type(uint256).max,
//     //                 deadline: block.timestamp + 100000,
//     //                 minAmountOut: 0,
//     //                 referralCode: 0
//     //             })
//     //         ),
//     //         operation: uint8(Enum.Operation.Call)
//     //     });

//     //     vm.prank(operator);
//     //     transactionModuleA.execute(transactions);

//     //     assertEq(USDC.balanceOf(address(fundAChild1)), 0);
//     //     assertEq(USDC.balanceOf(address(fundAChild2)), 0);
//     //     assertEq(USDC.balanceOf(address(fundA)), 2_000_000);
//     //     assertEq(USDC.balanceOf(address(fundB)), 0);
//     //     assertEq(
//     //         oracleRouter.getQuote(0, address(fundA), address(p_fundA.unitOfAccount())), fundATvl
//     //     );
//     }
// }
