// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity ^0.8.0;

import "@src/modules/deposit/Structs.sol";
import "@openzeppelin-contracts/utils/math/SignedMath.sol";
import "@src/libs/Constants.sol";
import {TestBasePeriphery} from "./TestBasePeriphery.sol";
import {Errors} from "@src/libs/Errors.sol";
import {MessageHashUtils} from "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@permit2/src/interfaces/IAllowanceTransfer.sol";
import {IPermit2} from "@permit2/src/interfaces/IPermit2.sol";

uint256 constant MAX_NET_EXIT_FEE_IN_BPS = 2_000;
uint256 constant MAX_NET_PERFORMANCE_FEE_IN_BPS = 7_000;
uint256 constant MAX_NET_ENTRANCE_FEE_IN_BPS = 5_000;
uint256 constant MAX_NET_MANAGEMENT_FEE_IN_BPS = 5_000;

contract TestPeripheryFees is TestBasePeriphery {
    using SignedMath for int256;

    address aliceFeeRecipient = makeAddr("AliceFeeRecipient");
    address receiver = makeAddr("Receiver");

    function setUp() public override(TestBasePeriphery) {
        TestBasePeriphery.setUp();

        vm.prank(address(fund));
        balanceOfOracle.addBalanceToValuate(address(mockToken1), address(fund));
    }

    struct TestEntranceFeeParams {
        uint160 depositAmount;
        uint8 brokerEntranceFeeInBps;
        uint8 protocolEntranceFeeInBps;
    }

    function test_deposit_with_entrance_fees(TestEntranceFeeParams memory params)
        public
        maxApproveAllPermit2(alice)
    {
        uint256 brokerEntranceFeeInBps =
            bound(uint256(params.brokerEntranceFeeInBps) * 25, 0, MAX_NET_ENTRANCE_FEE_IN_BPS);
        uint256 protocolEntranceFeeInBps = bound(
            uint256(params.protocolEntranceFeeInBps) * 25,
            0,
            MAX_NET_ENTRANCE_FEE_IN_BPS - brokerEntranceFeeInBps
        );

        uint256 depositAmount = params.depositAmount;
        vm.assume(
            depositAmount
                > depositModule.getGlobalAssetPolicy(address(mockToken1)).minimumDeposit + 1
        );
        vm.assume(depositAmount < type(uint160).max - 1);

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
                feeRecipient: aliceFeeRecipient,
                isPublic: false
            })
        );
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken1), true);
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken1), false);
        vm.stopPrank();

        mockToken1.mint(alice, depositAmount);

        uint256 sharesOut;

        vm.prank(alice);
        sharesOut = periphery.deposit(
            depositOrder(1, alice, receiver, address(mockToken1), type(uint256).max)
        );

        uint256 mintedShares = depositModule.internalVault().totalSupply();

        uint256 entranceFeeForBroker =
            brokerEntranceFeeInBps > 0 ? mintedShares * brokerEntranceFeeInBps / BP_DIVISOR : 0;
        uint256 entranceFeeForProtocol =
            protocolEntranceFeeInBps > 0 ? mintedShares * protocolEntranceFeeInBps / BP_DIVISOR : 0;

        assertApproxEqRel(
            mockToken1.balanceOf(address(fund)), depositAmount, 0.1e18, "Fund balance wrong"
        );
        assertApproxEqRel(
            depositModule.internalVault().balanceOf(receiver),
            sharesOut,
            0.1e18,
            "receiver balance wrong"
        );
        if (brokerEntranceFeeInBps > 0) {
            assertApproxEqRel(
                depositModule.internalVault().balanceOf(aliceFeeRecipient),
                entranceFeeForBroker,
                0.1e18,
                "Broker balance wrong"
            );
        }
        if (protocolEntranceFeeInBps > 0) {
            assertApproxEqRel(
                depositModule.internalVault().balanceOf(feeRecipient),
                entranceFeeForProtocol,
                0.1e18,
                "Protocol balance wrong"
            );
        }
    }

    struct TestExitFeeParams {
        uint32 depositAmount;
        uint32 profitAmount;
        uint8 brokerExitFeeInBps;
        uint8 protocolExitFeeInBps;
        uint8 brokerPerformanceFeeInBps;
        uint8 protocolPerformanceFeeInBps;
    }

    function test_deposit_withdraw_all_with_exit_fees_with_profit(TestExitFeeParams memory params)
        public
        maxApproveAllPermit2(alice)
    {
        /// @notice that the fees are fuzzed in 25bps increments
        uint256 protocolExitFeeInBps = uint256(params.protocolExitFeeInBps) * 25;
        uint256 brokerExitFeeInBps = uint256(params.brokerExitFeeInBps) * 25;
        vm.assume(brokerExitFeeInBps + protocolExitFeeInBps < MAX_NET_EXIT_FEE_IN_BPS);

        uint256 brokerPerformanceFeeInBps = uint256(params.brokerPerformanceFeeInBps) * 25;
        uint256 protocolPerformanceFeeInBps = uint256(params.protocolPerformanceFeeInBps) * 25;
        vm.assume(
            protocolPerformanceFeeInBps + brokerPerformanceFeeInBps < MAX_NET_PERFORMANCE_FEE_IN_BPS
        );

        uint256 depositAmount = params.depositAmount * mock1Unit;
        vm.assume(
            depositAmount
                > depositModule.getGlobalAssetPolicy(address(mockToken1)).minimumDeposit + 1
        );
        uint256 profitAmount = params.profitAmount * mock1Unit;
        vm.assume(profitAmount < 100000 * depositAmount);

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
                feeRecipient: aliceFeeRecipient,
                isPublic: false
            })
        );

        periphery.enableBrokerAssetPolicy(accountId, address(mockToken1), true);
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken1), false);
        vm.stopPrank();

        mockToken1.mint(alice, depositAmount);

        vm.prank(alice);
        periphery.deposit(depositOrder(1, alice, alice, address(mockToken1), type(uint256).max));

        /// simulate that the fund makes profit or loses money
        mockToken1.mint(address(fund), profitAmount);

        uint256 exitFeeForBroker = brokerExitFeeInBps > 0
            ? mockToken1.balanceOf(address(fund)) * brokerExitFeeInBps / BP_DIVISOR
            : 0;
        uint256 exitFeeForProtocol = protocolExitFeeInBps > 0
            ? mockToken1.balanceOf(address(fund)) * protocolExitFeeInBps / BP_DIVISOR
            : 0;

        vm.prank(alice);
        periphery.withdraw(
            withdrawOrder(1, alice, receiver, address(mockToken1), type(uint256).max)
        );

        uint256 performanceFeeForBroker = brokerPerformanceFeeInBps > 0 && profitAmount > 0
            ? profitAmount * brokerPerformanceFeeInBps / 10_000
            : 0;
        uint256 performanceFeeForProtocol = protocolPerformanceFeeInBps > 0 && profitAmount > 0
            ? profitAmount * protocolPerformanceFeeInBps / 10_000
            : 0;

        assertApproxEqRel(
            depositAmount + profitAmount - performanceFeeForBroker - performanceFeeForProtocol
                - exitFeeForBroker - exitFeeForProtocol,
            mockToken1.balanceOf(receiver),
            0.1e18,
            "receiver balance wrong"
        );
        assertApproxEqRel(
            mockToken1.balanceOf(aliceFeeRecipient),
            performanceFeeForBroker + exitFeeForBroker,
            0.1e18,
            "broker fee wrong"
        );
        assertApproxEqRel(
            mockToken1.balanceOf(feeRecipient),
            performanceFeeForProtocol + exitFeeForProtocol,
            0.1e18,
            "protocol fee wrong"
        );

        assertEq(internalVault.balanceOf(alice), 0, "alice LP balance wrong");
        assertEq(internalVault.totalSupply(), 0, "total supply wrong");
    }

    function test_management_fee(
        uint16 managementFeeRateInBps,
        uint256 timeDelta1,
        uint256 timeDelta2,
        uint256 timeDelta3
    ) public maxApproveAllPermit2(alice) {
        vm.assume(managementFeeRateInBps < MAX_NET_MANAGEMENT_FEE_IN_BPS);
        timeDelta1 = bound(timeDelta1, 1, 10 * 365 days);
        timeDelta2 = bound(timeDelta2, 1, 10 * 365 days);
        timeDelta3 = bound(timeDelta3, 1, 10 * 365 days);

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
                feeRecipient: address(0),
                isPublic: false
            })
        );
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken1), true);
        periphery.enableBrokerAssetPolicy(accountId, address(mockToken1), false);
        vm.stopPrank();

        mockToken1.mint(alice, 50 ether);

        vm.prank(alice);
        periphery.deposit(depositOrder(1, alice, alice, address(mockToken1), type(uint256).max));
        assertEq(
            depositModule.internalVault().balanceOf(alice),
            depositModule.internalVault().totalSupply()
        );

        /// @notice that now blocks have passed, so no time has passed, so there is no management fee
        assertEq(depositModule.internalVault().balanceOf(managementFeeRecipient), 0);

        mockToken1.mint(alice, 50 ether);

        vm.prank(alice);
        periphery.withdraw(withdrawOrder(1, alice, alice, address(mockToken1), type(uint256).max));
        assertEq(
            depositModule.internalVault().balanceOf(alice),
            depositModule.internalVault().totalSupply()
        );

        /// @notice that now blocks have passed, so no time has passed, so there is no management fee
        assertEq(depositModule.internalVault().balanceOf(managementFeeRecipient), 0);

        /// now we simulate time passing
        vm.warp(block.timestamp + timeDelta1);

        uint256 managementFee1 = depositModule.internalVault().totalSupply() * timeDelta1
            * managementFeeRateInBps / BP_DIVISOR / 365 days;

        mockToken1.mint(alice, 50 ether);

        vm.prank(alice);
        periphery.deposit(depositOrder(1, alice, alice, address(mockToken1), type(uint256).max));
        assertEq(
            depositModule.internalVault().balanceOf(alice),
            depositModule.internalVault().totalSupply() - managementFee1
        );

        /// @notice now the management fee should have been minted to the management fee recipient
        /// since time has passed between deposits
        assertEq(depositModule.internalVault().balanceOf(managementFeeRecipient), managementFee1);

        vm.warp(block.timestamp + timeDelta2);

        uint256 managementFee2 = depositModule.internalVault().totalSupply() * timeDelta2
            * managementFeeRateInBps / BP_DIVISOR / 365 days;

        mockToken1.mint(alice, 50 ether);

        vm.prank(alice);
        periphery.deposit(depositOrder(1, alice, alice, address(mockToken1), type(uint256).max));

        assertApproxEqRel(
            depositModule.internalVault().balanceOf(alice),
            depositModule.internalVault().totalSupply() - managementFee1 - managementFee2,
            0.1e18,
            "Alice balance wrong"
        );

        assertApproxEqRel(
            depositModule.internalVault().balanceOf(managementFeeRecipient),
            managementFee1 + managementFee2,
            0.1e18,
            "Management fee recipient balance wrong"
        );

        vm.warp(block.timestamp + timeDelta3);

        uint256 managementFee3 = depositModule.internalVault().totalSupply() * timeDelta3
            * managementFeeRateInBps / BP_DIVISOR / 365 days;

        vm.prank(alice);
        periphery.withdraw(withdrawOrder(1, alice, alice, address(mockToken1), type(uint256).max));

        assertApproxEqRel(
            depositModule.internalVault().balanceOf(managementFeeRecipient),
            managementFee1 + managementFee2 + managementFee3,
            0.1e18,
            "Management fee recipient balance wrong"
        );

        assertEq(depositModule.internalVault().balanceOf(alice), 0);
    }
}
