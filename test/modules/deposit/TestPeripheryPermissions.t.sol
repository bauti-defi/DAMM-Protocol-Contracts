// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity ^0.8.0;

import {EulerRouter} from "@euler-price-oracle/EulerRouter.sol";
import {Periphery, IAccessControl, IERC721Errors} from "@src/modules/deposit/Periphery.sol";
import "@src/modules/deposit/Structs.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";
import {MockPriceOracle} from "@test/mocks/MockPriceOracle.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@src/libs/Errors.sol";
import {DepositLibs} from "@src/modules/deposit/DepositLibs.sol";
import {TestBasePeriphery} from "./TestBasePeriphery.sol";
import {IPermit2} from "@permit2/src/interfaces/IPermit2.sol";
import "@src/libs/Constants.sol";

contract TestPeripheryPermissions is TestBasePeriphery {
    using MessageHashUtils for bytes;
    using DepositLibs for BrokerAccountInfo;

    function setUp() public override(TestBasePeriphery) {
        TestBasePeriphery.setUp();

        mockToken1.mint(alice, 100_000_000 * mock1Unit);

        vm.prank(address(fund));
        balanceOfOracle.addBalanceToValuate(address(mockToken1), address(fund));

        vm.startPrank(alice);
        IPermit2(permit2).approve(
            address(depositModule.internalVault()),
            address(periphery),
            type(uint160).max,
            type(uint48).max
        );
        IPermit2(permit2).approve(
            address(mockToken1), address(periphery), type(uint160).max, type(uint48).max
        );
        vm.stopPrank();
    }

    function test_only_account_manager_can_enable_broker_asset_policy(address attacker)
        public
        openAccount(alice, 10000, false, false)
    {
        vm.assume(attacker != accountManager);
        vm.assume(attacker != address(fund));

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                ACCOUNT_MANAGER_ROLE
            )
        );
        periphery.enableBrokerAssetPolicy(1, address(mockToken1), true);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                ACCOUNT_MANAGER_ROLE
            )
        );
        periphery.enableBrokerAssetPolicy(1, address(mockToken1), false);

        assertFalse(periphery.isBrokerAssetPolicyEnabled(1, address(mockToken1), true));
        assertFalse(periphery.isBrokerAssetPolicyEnabled(1, address(mockToken1), false));

        vm.startPrank(address(fund));
        periphery.enableBrokerAssetPolicy(1, address(mockToken1), true);
        periphery.enableBrokerAssetPolicy(1, address(mockToken1), false);
        vm.stopPrank();

        assertTrue(periphery.isBrokerAssetPolicyEnabled(1, address(mockToken1), true));
        assertTrue(periphery.isBrokerAssetPolicyEnabled(1, address(mockToken1), false));
    }

    function test_broker_can_only_deposit_withdraw_intent_enabled_assets()
        public
        openAccount(alice, 10000, false, false)
        maxApproveAllPermit2(alice)
    {
        SignedDepositIntent memory dOrder = depositIntent(
            1,
            alice,
            alicePK,
            alice,
            address(mockToken1),
            type(uint256).max,
            0,
            0,
            periphery.getAccountNonce(1)
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AssetUnavailable.selector);
        periphery.intentDeposit(dOrder);

        _enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), true);

        vm.prank(relayer);
        periphery.intentDeposit(dOrder);

        SignedWithdrawIntent memory wOrder = signedWithdrawIntent(
            1,
            alice,
            alicePK,
            alice,
            address(mockToken1),
            type(uint256).max,
            0,
            0,
            periphery.getAccountNonce(1)
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AssetUnavailable.selector);
        periphery.intentWithdraw(wOrder);

        _enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), false);

        vm.prank(relayer);
        periphery.intentWithdraw(wOrder);
    }

    function test_broker_can_only_deposit_withdraw_enabled_assets()
        public
        openAccount(alice, 10000, false, false)
        maxApproveAllPermit2(alice)
    {
        DepositOrder memory dOrder =
            depositOrder(1, alice, alice, address(mockToken1), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(Errors.Deposit_AssetUnavailable.selector);
        periphery.deposit(dOrder);

        _enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), true);

        vm.prank(alice);
        periphery.deposit(dOrder);

        WithdrawOrder memory wOrder =
            withdrawOrder(1, alice, alice, address(mockToken1), type(uint256).max);

        vm.prank(alice);
        vm.expectRevert(Errors.Deposit_AssetUnavailable.selector);
        periphery.withdraw(wOrder);

        _enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), false);

        vm.prank(alice);
        periphery.withdraw(wOrder);
    }

    function test_only_account_signature_is_valid()
        public
        openAccount(alice, 10000, false, false)
        enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), true)
        enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), false)
    {
        SignedDepositIntent memory dOrder = signdepositIntent(
            unsignedDepositIntent(1, alice, alice, address(mockToken1), mock1Unit, 0, 0, 0),
            uint256(123)
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidSignature.selector);
        periphery.intentDeposit(dOrder);

        SignedWithdrawIntent memory wOrder = signsignedWithdrawIntent(
            unsignedWithdrawIntent(1, alice, alice, address(mockToken1), mock1Unit, 0, 0, 0),
            uint256(123)
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidSignature.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_only_enabled_account_can_deposit_withdraw(uint256 accountId_) public {
        SignedDepositIntent memory dOrder = depositIntent(
            accountId_, alice, alicePK, alice, address(mockToken1), mock1Unit, 0, 0, 0
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountDoesNotExist.selector);
        periphery.intentDeposit(dOrder);

        SignedWithdrawIntent memory wOrder = signedWithdrawIntent(
            accountId_, alice, alicePK, alice, address(mockToken1), mock1Unit, 0, 0, 0
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountDoesNotExist.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_only_active_account_can_deposit_withdraw()
        public
        openAccount(alice, 100000, false, false)
    {
        {
            _enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), true);
            _enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), false);

            vm.prank(address(fund));
            periphery.pauseAccount(1);
        }

        SignedDepositIntent memory dOrder =
            depositIntent(1, alice, alicePK, alice, address(mockToken1), mock1Unit, 0, 0, 0);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountNotActive.selector);
        periphery.intentDeposit(dOrder);

        SignedWithdrawIntent memory wOrder =
            signedWithdrawIntent(1, alice, alicePK, alice, address(mockToken1), mock1Unit, 0, 0, 0);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountNotActive.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_order_must_have_valid_nonce(uint256 nonce_)
        public
        openAccount(alice, 1000000, false, false)
    {
        vm.assume(nonce_ > 1);

        _enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), true);
        _enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), false);

        SignedDepositIntent memory dOrder =
            depositIntent(1, alice, alicePK, alice, address(mockToken1), mock1Unit, 0, 0, nonce_);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidNonce.selector);
        periphery.intentDeposit(dOrder);

        SignedWithdrawIntent memory wOrder = signedWithdrawIntent(
            1, alice, alicePK, alice, address(mockToken1), mock1Unit, 0, 0, nonce_
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidNonce.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_order_must_be_within_deadline(uint256 timestamp_)
        public
        openAccount(alice, 100000000 * 2, false, false)
    {
        vm.assume(timestamp_ > 10000);
        vm.assume(timestamp_ < 100000000 * 2);

        SignedDepositIntent memory dOrder =
            depositIntent(1, alice, alicePK, alice, address(mockToken1), mock1Unit, 0, 0, 0);

        // increase timestamp
        vm.warp(timestamp_);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OrderExpired.selector);
        periphery.intentDeposit(dOrder);

        // reset timestamp to generate valid order
        vm.warp(0);

        SignedWithdrawIntent memory wOrder =
            signedWithdrawIntent(1, alice, alicePK, alice, address(mockToken1), mock1Unit, 0, 0, 0);

        // increase timestamp
        vm.warp(timestamp_);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OrderExpired.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_order_chain_id_must_match(uint256 chainId_)
        public
        openAccount(alice, 1000000, false, false)
        enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), true)
        enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), false)
    {
        vm.assume(chainId_ != block.chainid);

        DepositIntent memory dIntent =
            unsignedDepositIntent(1, alice, alice, address(mockToken1), mock1Unit, 0, 0, 0);

        dIntent.chainId = chainId_;

        SignedDepositIntent memory dOrder = signdepositIntent(dIntent, alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidChain.selector);
        periphery.intentDeposit(dOrder);

        WithdrawIntent memory wIntent =
            unsignedWithdrawIntent(1, alice, alice, address(mockToken1), mock1Unit, 0, 0, 0);

        wIntent.chainId = chainId_;

        SignedWithdrawIntent memory wOrder = signsignedWithdrawIntent(wIntent, alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidChain.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_only_non_expired_account_can_deposit(uint256 timestamp)
        public
        openAccount(alice, 1, false, false)
        enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), true)
        maxApproveAllPermit2(alice)
    {
        vm.assume(timestamp > 1);
        vm.assume(timestamp < 100000000 * 2);

        vm.prank(address(fund));
        periphery.enableBrokerAssetPolicy(1, address(mockToken1), true);

        vm.warp(timestamp);

        SignedDepositIntent memory dOrder =
            depositIntent(1, alice, alicePK, alice, address(mockToken1), mock1Unit, 0, 0, 0);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountExpired.selector);
        periphery.intentDeposit(dOrder);
    }

    function test_expired_account_can_withdraw()
        public
        openAccount(alice, 1000, false, false)
        enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), true)
        enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), false)
        maxApproveAllPermit2(alice)
    {
        SignedDepositIntent memory dOrder =
            depositIntent(1, alice, alicePK, alice, address(mockToken1), type(uint256).max, 0, 0, 0);

        vm.prank(relayer);
        periphery.intentDeposit(dOrder);

        assertTrue(depositModule.internalVault().balanceOf(alice) > 0);
        assertFalse(periphery.getAccountInfo(1).isExpired());

        vm.warp(100000000 * 2);

        assertTrue(periphery.getAccountInfo(1).isExpired());

        SignedWithdrawIntent memory wOrder = signedWithdrawIntent(
            1, alice, alicePK, alice, address(mockToken1), type(uint256).max, 0, 0, 1
        );

        vm.prank(relayer);
        periphery.intentWithdraw(wOrder);

        assertTrue(depositModule.internalVault().balanceOf(alice) == 0);
    }

    function test_only_allowed_assets_can_be_deposited_or_withdrawn(address asset)
        public
        openAccount(alice, 1000000, false, false)
    {
        vm.assume(asset != address(mockToken1));
        vm.assume(asset != address(mockToken2));

        SignedDepositIntent memory dOrder =
            depositIntent(1, alice, alicePK, alice, asset, mock2Unit, 0, 0, 0);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AssetUnavailable.selector);
        periphery.intentDeposit(dOrder);

        SignedWithdrawIntent memory wOrder =
            signedWithdrawIntent(1, alice, alicePK, alice, asset, mock2Unit, 0, 0, 0);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AssetUnavailable.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_only_manager_role_or_fund_can_pause_unpause_account(address attacker, bool asFund)
        public
        openAccount(alice, 1000000, false, false)
    {
        vm.assume(attacker != accountManager);
        vm.assume(attacker != address(fund));

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                ACCOUNT_MANAGER_ROLE
            )
        );
        periphery.pauseAccount(1);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                ACCOUNT_MANAGER_ROLE
            )
        );
        periphery.unpauseAccount(1);

        address pauser = asFund ? address(fund) : accountManager;

        vm.prank(pauser);
        periphery.pauseAccount(1);

        assertTrue(periphery.getAccountInfo(1).state == AccountState.PAUSED);

        vm.prank(pauser);
        periphery.unpauseAccount(1);

        assertTrue(periphery.getAccountInfo(1).state == AccountState.ACTIVE);
    }

    function test_only_account_manager_or_fund_can_close_account(address attacker, bool asFund)
        public
        openAccount(alice, 1000000, false, false)
    {
        vm.assume(attacker != accountManager);
        vm.assume(attacker != address(fund));

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                ACCOUNT_MANAGER_ROLE
            )
        );
        periphery.closeAccount(1);

        address closer = asFund ? address(fund) : accountManager;

        vm.prank(closer);
        periphery.closeAccount(1);

        assertTrue(periphery.getAccountInfo(1).state == AccountState.CLOSED);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        periphery.ownerOf(1);
    }

    function test_only_pauser_or_fund_role_can_pause_unpause_module(
        address attacker,
        address pauser,
        bool asFund
    ) public {
        vm.assume(attacker != address(fund));
        vm.assume(attacker != address(0));
        vm.assume(attacker != pauser);
        vm.assume(pauser != address(fund));
        vm.assume(pauser != address(0));

        address thePauser = asFund ? address(fund) : pauser;

        if (!asFund) {
            vm.prank(address(fund));
            periphery.grantRole(PAUSER_ROLE, thePauser);
        }

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, PAUSER_ROLE
            )
        );
        periphery.pause();

        vm.prank(thePauser);
        periphery.pause();

        assertTrue(periphery.paused());

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, PAUSER_ROLE
            )
        );
        periphery.unpause();

        vm.prank(thePauser);
        periphery.unpause();

        assertFalse(periphery.paused());

        vm.prank(thePauser);
        periphery.pause();

        assertTrue(periphery.paused());

        vm.prank(thePauser);
        periphery.unpause();

        assertFalse(periphery.paused());
    }

    function test_cannot_transfer_souldbound_broker_account(address attacker)
        public
        openAccount(alice, 1000000, false, false)
    {
        vm.prank(attacker);
        vm.expectRevert(Errors.Deposit_AccountNotTransferable.selector);
        periphery.transferFrom(alice, bob, 1);

        vm.prank(alice);
        vm.expectRevert(Errors.Deposit_AccountNotTransferable.selector);
        periphery.transferFrom(alice, bob, 1);

        vm.prank(attacker);
        vm.expectRevert(Errors.Deposit_AccountNotTransferable.selector);
        periphery.safeTransferFrom(alice, bob, 1);

        vm.prank(alice);
        vm.expectRevert(Errors.Deposit_AccountNotTransferable.selector);
        periphery.safeTransferFrom(alice, bob, 1);
    }

    function test_can_transfer_non_soulbound_broker_account()
        public
        openAccount(alice, 2 days, true, false)
    {
        address receiver = makeAddr("receiver");

        vm.prank(alice);
        periphery.transferFrom(alice, receiver, 1);

        assertEq(periphery.ownerOf(1), receiver);

        vm.prank(alice);
        vm.expectRevert();
        periphery.transferFrom(alice, receiver, 1);

        assertEq(periphery.ownerOf(1), receiver);

        vm.prank(receiver);
        periphery.safeTransferFrom(receiver, alice, 1);

        assertEq(periphery.ownerOf(1), alice);
    }

    function test_only_controller_can_change_protocol_fee_recipient(address attacker) public {
        vm.assume(attacker != address(fund) && attacker != address(0));

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, CONTROLLER_ROLE
            )
        );
        periphery.setProtocolFeeRecipient(attacker);

        vm.prank(address(fund));
        periphery.setProtocolFeeRecipient(attacker);

        assertTrue(periphery.protocolFeeRecipient() == attacker);
    }

    function test_only_controller_can_set_management_fee(address attacker) public {
        vm.assume(attacker != address(fund));

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, CONTROLLER_ROLE
            )
        );
        periphery.setManagementFeeRateInBps(100);

        vm.prank(address(fund));
        periphery.setManagementFeeRateInBps(100);

        assertEq(periphery.managementFeeRateInBps(), 100);
    }

    function test_management_fee_cannot_be_set_above_100_percent(uint16 rateInBps) public {
        vm.prank(address(fund));
        if (rateInBps <= BP_DIVISOR) {
            periphery.setManagementFeeRateInBps(rateInBps);
        } else {
            vm.expectRevert(Errors.Deposit_InvalidManagementFeeRate.selector);
            periphery.setManagementFeeRateInBps(rateInBps);
        }
    }

    function test_set_broker_fee_recipient(address attacker, address newRecipient) public {
        address broker = makeAddr("broker");

        vm.assume(attacker != broker);
        vm.assume(newRecipient != address(0));

        _openAccount(broker, 2 days, false, false);

        vm.prank(attacker);
        vm.expectRevert(Errors.Deposit_AccountDoesNotExist.selector);
        periphery.setBrokerFeeRecipient(2, newRecipient);

        vm.prank(attacker);
        vm.expectRevert(Errors.Deposit_OnlyAccountOwner.selector);
        periphery.setBrokerFeeRecipient(1, newRecipient);

        vm.prank(broker);
        periphery.setBrokerFeeRecipient(1, newRecipient);

        assertEq(periphery.getAccountInfo(1).feeRecipient, newRecipient);
    }
}
