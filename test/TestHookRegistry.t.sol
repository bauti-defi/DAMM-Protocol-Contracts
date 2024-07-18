// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test, console2} from "@forge-std/Test.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {SafeUtils, SafeTransaction} from "@test/utils/SafeUtils.sol";
import "@src/modules/trading/Hooks.sol";
import "@src/modules/trading/HookRegistry.sol";
import "@src/libs/Errors.sol";

contract TestHookRegistry is Test, TestBaseGnosis, TestBaseProtocol {
    using SafeUtils for SafeL2;

    address internal fundAdmin;
    uint256 internal fundAdminPK;
    SafeL2 internal fund;
    HookRegistry internal hookRegistry;
    address operator;

    function setUp() public override(TestBaseGnosis, TestBaseProtocol) {
        TestBaseGnosis.setUp();
        TestBaseProtocol.setUp();

        operator = makeAddr("Operator");

        (fundAdmin, fundAdminPK) = makeAddrAndKey("FundAdmin");
        vm.deal(fundAdmin, 1000 ether);

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;

        fund = deploySafe(admins, 1);
        assertTrue(address(fund) != address(0), "Failed to deploy fund");
        assertTrue(fund.isOwner(fundAdmin), "Fund admin not owner");

        vm.deal(address(fund), 1000 ether);

        hookRegistry = HookRegistry(
            deployContract(
                payable(address(fund)),
                fundAdmin,
                fundAdminPK,
                address(createCall),
                bytes32("hookRegistry"),
                0,
                abi.encodePacked(type(HookRegistry).creationCode, abi.encode(address(fund)))
            )
        );

        vm.label(address(hookRegistry), "HookRegistry");

        assertEq(hookRegistry.fund(), address(fund), "HookRegistry fund not set");
    }

    modifier withHook(HookConfig memory config) {
        vm.prank(address(fund));
        hookRegistry.setHooks(config);
        _;
    }

    function mock_hook() private view returns (HookConfig memory) {
        return HookConfig({
            operator: operator,
            target: address(this),
            beforeTrxHook: address(0),
            afterTrxHook: address(0),
            targetSelector: bytes4(keccak256("increment(uint256)")),
            operation: uint8(Enum.Operation.Call)
        });
    }

    function test_set_hook() public {
        HookConfig memory config = mock_hook();

        //create safe transaction as admin. this transaction will call the setHook() on the tradingModule
        bytes memory transaction = abi.encodeWithSelector(hookRegistry.setHooks.selector, config);

        bool success = fund.executeTrx(
            fundAdminPK,
            SafeTransaction({
                value: 0,
                target: address(hookRegistry),
                operation: Enum.Operation.Call,
                transaction: transaction
            })
        );

        assertTrue(success, "Failed to set hook");

        Hooks memory hooks = hookRegistry.getHooks(
            config.operator, config.target, config.operation, config.targetSelector
        );

        assertTrue(hooks.defined, "Hook not defined");
    }

    function test_only_fund_can_set_hook(address attacker) public {
        vm.assume(attacker != address(fund));

        vm.expectRevert(Errors.OnlyFund.selector);
        vm.prank(attacker);
        hookRegistry.setHooks(mock_hook());
    }

    function test_unset_hook() public {
        HookConfig memory config = mock_hook();

        vm.prank(address(fund));
        hookRegistry.setHooks(config);

        //create safe transaction as admin. this transaction will call the removeHook() on the tradingModule
        bytes memory transaction = abi.encodeWithSelector(hookRegistry.removeHooks.selector, config);

        bool success = fund.executeTrx(
            fundAdminPK,
            SafeTransaction({
                value: 0,
                target: address(hookRegistry),
                operation: Enum.Operation.Call,
                transaction: transaction
            })
        );

        assertTrue(success, "Failed to remove hook");

        Hooks memory hooks = hookRegistry.getHooks(
            config.operator, config.target, config.operation, config.targetSelector
        );

        assertFalse(hooks.defined, "Hook not removed");
    }

    function test_only_fund_can_unset_hook(address attacker) public withHook(mock_hook()) {
        vm.assume(attacker != address(fund));

        vm.expectRevert(Errors.OnlyFund.selector);
        vm.prank(attacker);
        hookRegistry.removeHooks(mock_hook());
    }
}
