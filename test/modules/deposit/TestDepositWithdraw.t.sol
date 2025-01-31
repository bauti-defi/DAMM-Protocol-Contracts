// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity ^0.8.0;

import "@src/modules/deposit/Structs.sol";
import "@openzeppelin-contracts/utils/math/SignedMath.sol";
import "@src/libs/Constants.sol";
import {TestBaseDeposit} from "./TestBaseDeposit.sol";
import {Errors} from "@src/libs/Errors.sol";

uint256 constant MAX_NET_EXIT_FEE_IN_BPS = 5_000;
uint256 constant MAX_NET_PERFORMANCE_FEE_IN_BPS = 7_000;
uint256 constant MAX_NET_ENTRANCE_FEE_IN_BPS = 5_000;
uint256 constant MAX_NET_MANAGEMENT_FEE_IN_BPS = 5_000;

contract TestDepositWithdraw is TestBaseDeposit {
    using SignedMath for int256;

    function setUp() public override(TestBaseDeposit) {
        TestBaseDeposit.setUp();

        vm.prank(address(fund));
        balanceOfOracle.addBalanceToValuate(address(mockToken1), address(fund));
    }

    struct TestEntranceFeeParams {
        bool useIntent;
        uint32 depositAmount;
        uint8 brokerEntranceFeeInBps;
        uint8 protocolEntranceFeeInBps;
    }

    function test_deposit_with_entrance_fees(TestEntranceFeeParams memory params)
        public
        approveAllPeriphery(alice)
    {
        vm.assume(params.depositAmount > 10);

        uint256 brokerEntranceFeeInBps = uint256(params.brokerEntranceFeeInBps) * 25;
        uint256 protocolEntranceFeeInBps = uint256(params.protocolEntranceFeeInBps) * 25;
        vm.assume(brokerEntranceFeeInBps + protocolEntranceFeeInBps < MAX_NET_ENTRANCE_FEE_IN_BPS);

        /// @notice we cast to uint256 because we want to test the max values
        uint256 depositAmount = params.depositAmount * mock1Unit;

        vm.startPrank(address(fund));
        uint256 accountId = periphery.openAccount(
            CreateAccountParams({
                transferable: false,
                user: alice,
                ttl: 100000000,
                shareMintLimit: type(uint256).max,
                brokerPerformanceFeeInBps: 0,
                protocolPerformanceFeeInBps: 0,
                brokerEntranceFeeInBps: brokerEntranceFeeInBps,
                protocolEntranceFeeInBps: protocolEntranceFeeInBps,
                brokerExitFeeInBps: 0,
                protocolExitFeeInBps: 0,
                feeRecipient: address(0)
            })
        );
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken1), true);
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken1), false);
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken2), true);
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken2), false);
        vm.stopPrank();

        mockToken1.mint(alice, depositAmount);

        address receiver = makeAddr("Receiver");

        uint256 sharesOut;

        /// alice deposits
        if (params.useIntent) {
            sharesOut = periphery.intentDeposit(
                depositIntent(
                    1,
                    receiver,
                    alicePK,
                    address(mockToken1),
                    type(uint256).max,
                    0,
                    0,
                    periphery.getAccountNonce(1)
                )
            );
        } else {
            vm.prank(alice);
            sharesOut =
                periphery.deposit(depositOrder(1, receiver, address(mockToken1), type(uint256).max));
        }

        uint256 entranceFeeForBroker =
            brokerEntranceFeeInBps > 0 ? sharesOut * brokerEntranceFeeInBps / BP_DIVISOR : 0;
        uint256 entranceFeeForProtocol =
            protocolEntranceFeeInBps > 0 ? sharesOut * protocolEntranceFeeInBps / BP_DIVISOR : 0;

        assertApproxEqRel(
            mockToken1.balanceOf(address(fund)), depositAmount, 0.1e18, "Fund balance wrong"
        );
        assertApproxEqRel(
            periphery.internalVault().balanceOf(receiver),
            sharesOut - entranceFeeForBroker - entranceFeeForProtocol,
            0.1e18,
            "Broker entrance fee balance wrong"
        );
        if (brokerEntranceFeeInBps > 0) {
            assertApproxEqRel(
                periphery.internalVault().balanceOf(alice),
                entranceFeeForBroker,
                0.1e18,
                "Broker entrance fee balance wrong"
            );
        }
        if (protocolEntranceFeeInBps > 0) {
            assertApproxEqRel(
                periphery.internalVault().balanceOf(feeRecipient),
                entranceFeeForProtocol,
                0.1e18,
                "Protocol entrance fee balance wrong"
            );
        }
    }

    struct TestExitFeeParams {
        bool useIntent;
        uint32 depositAmount;
        int32 profitAmount;
        uint8 brokerExitFeeInBps;
        uint8 protocolExitFeeInBps;
        uint8 brokerPerformanceFeeInBps;
        uint8 protocolPerformanceFeeInBps;
    }

    function test_deposit_withdraw_all_with_exit_fees(TestExitFeeParams memory params)
        public
        approveAllPeriphery(alice)
    {
        vm.assume(params.depositAmount > 10);

        /// @notice that the fees are fuzzed in 25bps increments
        uint256 protocolExitFeeInBps = uint256(params.protocolExitFeeInBps) * 25;
        uint256 brokerExitFeeInBps = uint256(params.brokerExitFeeInBps) * 25;
        vm.assume(brokerExitFeeInBps + protocolExitFeeInBps < MAX_NET_EXIT_FEE_IN_BPS);

        uint256 brokerPerformanceFeeInBps = uint256(params.brokerPerformanceFeeInBps) * 25;
        uint256 protocolPerformanceFeeInBps = uint256(params.protocolPerformanceFeeInBps) * 25;
        vm.assume(
            protocolPerformanceFeeInBps + brokerPerformanceFeeInBps < MAX_NET_PERFORMANCE_FEE_IN_BPS
        );

        /// @notice we cast to uint256 because we want to test the max values
        uint256 depositAmount = params.depositAmount * mock1Unit;
        int256 profitAmount = params.profitAmount * int256(mock1Unit);

        vm.assume(profitAmount.abs() > 1 * mock1Unit || profitAmount == 0);
        vm.assume(profitAmount.abs() < depositAmount);

        vm.startPrank(address(fund));
        uint256 accountId = periphery.openAccount(
            CreateAccountParams({
                transferable: false,
                user: alice,
                ttl: 100000000,
                shareMintLimit: type(uint256).max,
                brokerPerformanceFeeInBps: brokerPerformanceFeeInBps,
                protocolPerformanceFeeInBps: protocolPerformanceFeeInBps,
                brokerEntranceFeeInBps: 0,
                protocolEntranceFeeInBps: 0,
                brokerExitFeeInBps: brokerExitFeeInBps,
                protocolExitFeeInBps: protocolExitFeeInBps,
                feeRecipient: address(0)
            })
        );

        periphery.enableBrokerAssetPolicy(accountId, address(mockToken1), true);
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken1), false);
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken2), true);
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken2), false);
        vm.stopPrank();

        mockToken1.mint(alice, depositAmount);

        /// alice deposits
        if (params.useIntent) {
            periphery.intentDeposit(
                depositIntent(
                    1,
                    alice,
                    alicePK,
                    address(mockToken1),
                    type(uint256).max,
                    0,
                    0,
                    periphery.getAccountNonce(1)
                )
            );
        } else {
            vm.prank(alice);
            periphery.deposit(depositOrder(1, alice, address(mockToken1), type(uint256).max));
        }

        /// simulate that the fund makes profit or loses money
        if (profitAmount > 0) {
            mockToken1.mint(address(fund), profitAmount.abs());
        } else {
            vm.prank(address(fund));
            mockToken1.transfer(address(1), profitAmount.abs());
        }

        address claimer = makeAddr("Claimer");

        uint256 exitFeeForBroker = brokerExitFeeInBps > 0
            ? mockToken1.balanceOf(address(fund)) * brokerExitFeeInBps / BP_DIVISOR
            : 0;
        uint256 exitFeeForProtocol = protocolExitFeeInBps > 0
            ? mockToken1.balanceOf(address(fund)) * protocolExitFeeInBps / BP_DIVISOR
            : 0;

        if (params.useIntent) {
            periphery.intentWithdraw(
                signedWithdrawIntent(
                    1,
                    claimer,
                    alicePK,
                    address(mockToken1),
                    type(uint256).max,
                    0,
                    0,
                    periphery.getAccountNonce(1)
                )
            );
        } else {
            vm.prank(alice);
            periphery.withdraw(withdrawOrder(1, claimer, address(mockToken1), type(uint256).max));
        }

        uint256 performanceFeeForBroker = brokerPerformanceFeeInBps > 0 && profitAmount > 0
            ? profitAmount.abs() * brokerPerformanceFeeInBps / 10_000
            : 0;
        uint256 performanceFeeForProtocol = protocolPerformanceFeeInBps > 0 && profitAmount > 0
            ? profitAmount.abs() * protocolPerformanceFeeInBps / 10_000
            : 0;

        uint256 profit = profitAmount.abs() - performanceFeeForBroker - performanceFeeForProtocol;

        /// @notice you wont get exact amount out because of vault inflation attack protection
        if (profitAmount > 0) {
            assertApproxEqRel(
                mockToken1.balanceOf(claimer),
                depositAmount + profit - exitFeeForBroker - exitFeeForProtocol,
                0.1e18,
                "Claimer balance wrong when profit"
            );
            assertApproxEqRel(
                mockToken1.balanceOf(alice),
                performanceFeeForBroker + exitFeeForBroker,
                0.1e18,
                "broker fee wrong when profit"
            );
            assertApproxEqRel(
                mockToken1.balanceOf(feeRecipient),
                performanceFeeForProtocol + exitFeeForProtocol,
                0.1e18,
                "protocol fee wrong when profit"
            );
        } else {
            assertEq(
                mockToken1.balanceOf(claimer),
                depositAmount - profitAmount.abs() - exitFeeForBroker - exitFeeForProtocol,
                "Claimer balance wrong when no profit"
            );
            assertApproxEqRel(
                mockToken1.balanceOf(alice),
                exitFeeForBroker,
                0.1e18,
                "Broker fee wrong when no profit"
            );
            assertApproxEqRel(
                mockToken1.balanceOf(feeRecipient),
                exitFeeForProtocol,
                0.1e18,
                "Protocol fee wrong when no profit"
            );
        }

        assertEq(periphery.internalVault().balanceOf(alice), 0);
        assertEq(mockToken1.balanceOf(address(fund)), periphery.internalVault().totalAssets());
    }

    function test_management_fee(
        uint16 managementFeeRateInBps,
        uint256 timeDelta1,
        uint256 timeDelta2,
        uint256 timeDelta3
    ) public approveAllPeriphery(alice) {
        vm.assume(managementFeeRateInBps < MAX_NET_MANAGEMENT_FEE_IN_BPS);
        vm.assume(timeDelta1 > 0);
        vm.assume(timeDelta1 < 10 * 365 days);
        vm.assume(timeDelta2 > 0);
        vm.assume(timeDelta2 < 10 * 365 days);
        vm.assume(timeDelta3 > 0);
        vm.assume(timeDelta3 < 10 * 365 days);

        address managementFeeRecipient = makeAddr("ManagementFeeRecipient");

        vm.assume(managementFeeRecipient != address(0));

        vm.startPrank(address(fund));
        periphery.setManagementFeeRateInBps(managementFeeRateInBps);
        periphery.setProtocolFeeRecipient(managementFeeRecipient);
        uint256 accountId = periphery.openAccount(
            CreateAccountParams({
                transferable: false,
                user: alice,
                ttl: timeDelta1 + timeDelta2 + 1,
                shareMintLimit: type(uint256).max,
                brokerPerformanceFeeInBps: 0,
                protocolPerformanceFeeInBps: 0,
                brokerEntranceFeeInBps: 0,
                protocolEntranceFeeInBps: 0,
                brokerExitFeeInBps: 0,
                protocolExitFeeInBps: 0,
                feeRecipient: address(0)
            })
        );
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken1), true);
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken1), false);
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken2), true);
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken2), false);
        vm.stopPrank();

        mockToken1.mint(alice, 50 ether);

        vm.prank(alice);
        periphery.deposit(depositOrder(1, alice, address(mockToken1), type(uint256).max));
        assertEq(
            periphery.internalVault().balanceOf(alice), periphery.internalVault().totalSupply()
        );

        /// @notice that now blocks have passed, so no time has passed, so there is no management fee
        assertEq(periphery.internalVault().balanceOf(managementFeeRecipient), 0);

        mockToken1.mint(alice, 50 ether);

        vm.prank(alice);
        periphery.withdraw(withdrawOrder(1, alice, address(mockToken1), type(uint256).max));
        assertEq(
            periphery.internalVault().balanceOf(alice), periphery.internalVault().totalSupply()
        );

        /// @notice that now blocks have passed, so no time has passed, so there is no management fee
        assertEq(periphery.internalVault().balanceOf(managementFeeRecipient), 0);

        /// now we simulate time passing
        vm.warp(block.timestamp + timeDelta1);

        uint256 managementFee1 = periphery.internalVault().totalSupply() * timeDelta1
            * managementFeeRateInBps / BP_DIVISOR / 365 days;

        mockToken1.mint(alice, 50 ether);

        vm.prank(alice);
        periphery.deposit(depositOrder(1, alice, address(mockToken1), type(uint256).max));
        assertEq(
            periphery.internalVault().balanceOf(alice),
            periphery.internalVault().totalSupply() - managementFee1
        );

        /// @notice now the management fee should have been minted to the management fee recipient
        /// since time has passed between deposits
        assertEq(periphery.internalVault().balanceOf(managementFeeRecipient), managementFee1);

        vm.warp(block.timestamp + timeDelta2);

        uint256 managementFee2 = periphery.internalVault().totalSupply() * timeDelta2
            * managementFeeRateInBps / BP_DIVISOR / 365 days;

        mockToken1.mint(alice, 50 ether);

        vm.prank(alice);
        periphery.deposit(depositOrder(1, alice, address(mockToken1), type(uint256).max));

        assertApproxEqRel(
            periphery.internalVault().balanceOf(alice),
            periphery.internalVault().totalSupply() - managementFee1 - managementFee2,
            0.1e18,
            "Alice balance wrong"
        );

        assertApproxEqRel(
            periphery.internalVault().balanceOf(managementFeeRecipient),
            managementFee1 + managementFee2,
            0.1e18,
            "Management fee recipient balance wrong"
        );

        vm.warp(block.timestamp + timeDelta3);

        uint256 managementFee3 = periphery.internalVault().totalSupply() * timeDelta3
            * managementFeeRateInBps / BP_DIVISOR / 365 days;

        vm.prank(alice);
        periphery.withdraw(withdrawOrder(1, alice, address(mockToken1), type(uint256).max));

        assertApproxEqRel(
            periphery.internalVault().balanceOf(managementFeeRecipient),
            managementFee1 + managementFee2 + managementFee3,
            0.1e18,
            "Management fee recipient balance wrong"
        );

        assertEq(periphery.internalVault().balanceOf(alice), 0);
    }
}
