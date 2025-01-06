// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "@forge-std/Test.sol";

import {
    VaultConnectorHook,
    VaultConnectorHook_AccountDisabled,
    VaultConnectorHook_AccountEnabled,
    VaultConnectorHook_InvalidAccount,
    VaultConnectorHook_InvalidRecipient
} from "@src/hooks/damm/VaultConnectorHook.sol";
import {Errors} from "@src/libs/Errors.sol";
import {DepositOrder, WithdrawOrder} from "@src/modules/deposit/Structs.sol";
import {IPeriphery} from "@src/interfaces/IPeriphery.sol";
import {CALL} from "@src/libs/Constants.sol";

contract TestVaultConnectorHooks is Test {
    VaultConnectorHook private hook;
    address private fund;

    function setUp() public {
        fund = makeAddr("Fund");
        hook = new VaultConnectorHook(fund);
    }

    function test_enableAndDisableAccount(address periphery, uint256 id) public {
        assertFalse(hook.isAccountEnabled(periphery, id));
        vm.prank(fund);
        vm.expectEmit(true, true, false, true);
        emit VaultConnectorHook_AccountEnabled(periphery, id);
        hook.enableAccount(periphery, id);
        assertTrue(hook.isAccountEnabled(periphery, id));
        vm.prank(fund);
        vm.expectEmit(true, true, false, true);
        emit VaultConnectorHook_AccountDisabled(periphery, id);
        hook.disableAccount(periphery, id);
        assertFalse(hook.isAccountEnabled(periphery, id));
        emit VaultConnectorHook_AccountDisabled(periphery, id);
        assertFalse(hook.isAccountEnabled(periphery, id));
    }

    function test_onlyFundCanEnableAndDisableAccount(address notFund, address periphery, uint256 id)
        public
    {
        vm.assume(notFund != fund);

        vm.prank(notFund);
        vm.expectRevert(Errors.OnlyFund.selector);
        hook.enableAccount(periphery, id);
        vm.prank(notFund);
        vm.expectRevert(Errors.OnlyFund.selector);
        hook.disableAccount(periphery, id);
    }

    function test_onlyCallOperation(uint8 operation) public {
        vm.assume(operation != CALL);

        vm.prank(fund);
        vm.expectRevert(Errors.Hook_InvalidOperation.selector);
        hook.checkBeforeTransaction(address(0), IPeriphery.deposit.selector, operation, 0, "");
    }

    function test_onlyDepositAndWithdrawSelectors(bytes4 selector) public {
        vm.assume(selector != IPeriphery.deposit.selector);
        vm.assume(selector != IPeriphery.withdraw.selector);

        vm.prank(fund);
        vm.expectRevert(Errors.Hook_InvalidTargetSelector.selector);
        hook.checkBeforeTransaction(address(0), selector, CALL, 0, "");
    }

    function test_deposit(address periphery, uint256 id) public {
        vm.prank(fund);
        hook.enableAccount(periphery, id);

        DepositOrder memory depositOrder = DepositOrder({
            accountId: id,
            recipient: fund,
            asset: address(0),
            amount: 0,
            deadline: block.timestamp + 1 days,
            minSharesOut: 0,
            referralCode: 0
        });

        vm.prank(fund);
        hook.checkBeforeTransaction(
            periphery, IPeriphery.deposit.selector, CALL, 0, abi.encode(depositOrder)
        );
    }

    function test_invalidDepositAccount(address periphery, uint256 id) public {
        /// @notice we don't have the account enabled, so this should all be invalid
        DepositOrder memory depositOrder = DepositOrder({
            accountId: id,
            recipient: fund,
            asset: address(0),
            amount: 0,
            deadline: block.timestamp + 1 days,
            minSharesOut: 0,
            referralCode: 0
        });

        vm.prank(fund);
        vm.expectRevert(VaultConnectorHook_InvalidAccount.selector);
        hook.checkBeforeTransaction(
            periphery, IPeriphery.deposit.selector, CALL, 0, abi.encode(depositOrder)
        );
    }

    function test_invalidDepositRecipient(address periphery, uint256 id) public {
        vm.prank(fund);
        hook.enableAccount(periphery, id);

        address badRecipient = makeAddr("BadRecipient");

        vm.assume(badRecipient != fund);

        DepositOrder memory depositOrder = DepositOrder({
            accountId: id,
            recipient: badRecipient,
            asset: address(0),
            amount: 0,
            deadline: block.timestamp + 1 days,
            minSharesOut: 0,
            referralCode: 0
        });

        vm.prank(fund);
        vm.expectRevert(VaultConnectorHook_InvalidRecipient.selector);
        hook.checkBeforeTransaction(
            periphery, IPeriphery.deposit.selector, CALL, 0, abi.encode(depositOrder)
        );
    }

    function test_withdraw(address periphery, uint256 id) public {
        vm.prank(fund);
        hook.enableAccount(periphery, id);

        WithdrawOrder memory withdrawOrder = WithdrawOrder({
            accountId: id,
            to: fund,
            asset: address(0),
            shares: 0,
            deadline: block.timestamp + 1 days,
            minAmountOut: 0,
            referralCode: 0
        });

        vm.prank(fund);
        hook.checkBeforeTransaction(
            periphery, IPeriphery.withdraw.selector, CALL, 0, abi.encode(withdrawOrder)
        );
    }

    function test_invalidWithdrawAccount(address periphery, uint256 id) public {
        /// @notice we don't have the account enabled, so this should all be invalid
        WithdrawOrder memory withdrawOrder = WithdrawOrder({
            accountId: id,
            to: fund,
            asset: address(0),
            shares: 0,
            deadline: block.timestamp + 1 days,
            minAmountOut: 0,
            referralCode: 0
        });

        vm.prank(fund);
        vm.expectRevert(VaultConnectorHook_InvalidAccount.selector);
        hook.checkBeforeTransaction(
            periphery, IPeriphery.withdraw.selector, CALL, 0, abi.encode(withdrawOrder)
        );
    }

    function test_invalidWithdrawRecipient(address periphery, uint256 id) public {
        vm.prank(fund);
        hook.enableAccount(periphery, id);

        address badRecipient = makeAddr("BadRecipient");

        vm.assume(badRecipient != fund);

        WithdrawOrder memory withdrawOrder = WithdrawOrder({
            accountId: id,
            to: badRecipient,
            asset: address(0),
            shares: 0,
            deadline: block.timestamp + 1 days,
            minAmountOut: 0,
            referralCode: 0
        });

        vm.prank(fund);
        vm.expectRevert(VaultConnectorHook_InvalidRecipient.selector);
        hook.checkBeforeTransaction(
            periphery, IPeriphery.withdraw.selector, CALL, 0, abi.encode(withdrawOrder)
        );
    }
}
