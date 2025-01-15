// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TestBaseFund} from "@test/base/TestBaseFund.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {EulerRouter} from "@euler-price-oracle/EulerRouter.sol";
import {Periphery} from "@src/modules/deposit/Periphery.sol";
import {FundValuationOracle} from "@src/oracles/FundValuationOracle.sol";
import "@src/modules/deposit/Structs.sol";
import {NATIVE_ASSET, PAUSER_ROLE} from "@src/libs/Constants.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";
import {MockPriceOracle} from "@test/mocks/MockPriceOracle.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@src/libs/Errors.sol";
import {BP_DIVISOR} from "@src/libs/Constants.sol";
import {DepositLibs} from "@src/modules/deposit/DepositLibs.sol";
import {TestBaseDeposit} from "./TestBaseDeposit.sol";

contract TestDepositPermissions is TestBaseDeposit {
    using MessageHashUtils for bytes;
    using DepositLibs for BrokerAccountInfo;

    function setUp() public override(TestBaseDeposit) {
        TestBaseDeposit.setUp();

        mockToken1.mint(alice, 100_000_000 * mock1Unit);
    }

    modifier whitelistUser(address user_, uint256 ttl_, Role role_, bool transferable_) {
        _whitelistUser(user_, ttl_, role_, transferable_);

        _;
    }

    function _whitelistUser(address user_, uint256 ttl_, Role role_, bool transferable_) internal {
        vm.startPrank(address(fund));
        periphery.openAccount(
            CreateAccountParams({
                transferable: transferable_,
                user: user_,
                role: role_,
                ttl: ttl_,
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
        vm.stopPrank();
    }

    function test_only_account_signature_is_valid()
        public
        whitelistUser(alice, 10000, Role.USER, false)
    {
        SignedDepositIntent memory dOrder = signdepositIntent(
            unsignedDepositIntent(1, alice, address(mockToken1), mock1Unit, 0, 0, 0), uint256(123)
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidSignature.selector);
        periphery.intentDeposit(dOrder);

        SignedWithdrawIntent memory wOrder = signsignedWithdrawIntent(
            unsignedWithdrawIntent(1, alice, address(mockToken1), mock1Unit, 0, 0, 0), uint256(123)
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidSignature.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_only_enabled_account_can_deposit_withdraw(uint256 accountId_) public {
        SignedDepositIntent memory dOrder =
            depositIntent(accountId_, alice, alicePK, address(mockToken1), mock1Unit, 0, 0, 0);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountDoesNotExist.selector);
        periphery.intentDeposit(dOrder);

        SignedWithdrawIntent memory wOrder = signedWithdrawIntent(
            accountId_, alice, alicePK, address(mockToken1), mock1Unit, 0, 0, 0
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountDoesNotExist.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_only_active_account_can_deposit_withdraw()
        public
        whitelistUser(alice, 100000, Role.USER, false)
    {
        vm.prank(address(fund));
        periphery.pauseAccount(1);

        SignedDepositIntent memory dOrder =
            depositIntent(1, alice, alicePK, address(mockToken1), mock1Unit, 0, 0, 0);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountNotActive.selector);
        periphery.intentDeposit(dOrder);

        SignedWithdrawIntent memory wOrder =
            signedWithdrawIntent(1, alice, alicePK, address(mockToken1), mock1Unit, 0, 0, 0);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountNotActive.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_order_must_have_valid_nonce(uint256 nonce_)
        public
        whitelistUser(alice, 1000000, Role.USER, false)
    {
        vm.assume(nonce_ > 1);

        SignedDepositIntent memory dOrder =
            depositIntent(1, alice, alicePK, address(mockToken1), mock1Unit, 0, 0, nonce_);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidNonce.selector);
        periphery.intentDeposit(dOrder);

        SignedWithdrawIntent memory wOrder =
            signedWithdrawIntent(1, alice, alicePK, address(mockToken1), mock1Unit, 0, 0, nonce_);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidNonce.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_order_must_be_within_deadline(uint256 timestamp_)
        public
        whitelistUser(alice, 100000000 * 2, Role.USER, false)
    {
        vm.assume(timestamp_ > 10000);
        vm.assume(timestamp_ < 100000000 * 2);

        SignedDepositIntent memory dOrder =
            depositIntent(1, alice, alicePK, address(mockToken1), mock1Unit, 0, 0, 0);

        // increase timestamp
        vm.warp(timestamp_);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OrderExpired.selector);
        periphery.intentDeposit(dOrder);

        // reset timestamp to generate valid order
        vm.warp(0);

        SignedWithdrawIntent memory wOrder =
            signedWithdrawIntent(1, alice, alicePK, address(mockToken1), mock1Unit, 0, 0, 0);

        // increase timestamp
        vm.warp(timestamp_);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OrderExpired.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_order_chain_id_must_match(uint256 chainId_)
        public
        whitelistUser(alice, 1000000, Role.USER, false)
    {
        vm.assume(chainId_ != block.chainid);

        DepositIntent memory dIntent =
            unsignedDepositIntent(1, alice, address(mockToken1), mock1Unit, 0, 0, 0);

        dIntent.chaindId = chainId_;

        SignedDepositIntent memory dOrder = signdepositIntent(dIntent, alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidChain.selector);
        periphery.intentDeposit(dOrder);

        WithdrawIntent memory wIntent =
            unsignedWithdrawIntent(1, alice, address(mockToken1), mock1Unit, 0, 0, 0);

        wIntent.chaindId = chainId_;

        SignedWithdrawIntent memory wOrder = signsignedWithdrawIntent(wIntent, alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidChain.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_only_super_user_can_deposit_or_withdraw_permissioned_asset()
        public
        whitelistUser(alice, 1000000 * 2, Role.USER, false)
        whitelistUser(bob, 1000000 * 2, Role.SUPER_USER, false)
    {
        /// override asset policy to make it permissioned
        vm.prank(address(fund));
        periphery.enableAsset(
            address(mockToken2),
            AssetPolicy({
                minimumDeposit: 1000,
                minimumWithdrawal: 1000,
                canDeposit: true,
                canWithdraw: true,
                permissioned: true,
                enabled: true
            })
        );

        mockToken2.mint(bob, 100_000_000 * mock2Unit);
        mockToken2.mint(alice, 100_000_000 * mock2Unit);

        vm.startPrank(alice);
        mockToken2.approve(address(periphery), type(uint256).max);
        periphery.internalVault().approve(address(periphery), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        mockToken2.approve(address(periphery), type(uint256).max);
        periphery.internalVault().approve(address(periphery), type(uint256).max);
        vm.stopPrank();

        SignedDepositIntent memory dOrder =
            depositIntent(1, alice, alicePK, address(mockToken2), 1 * mock2Unit, 0, 0, 0);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OnlySuperUser.selector);
        periphery.intentDeposit(dOrder);

        dOrder = depositIntent(2, bob, bobPK, address(mockToken2), 10 * mock2Unit, 0, 0, 0);

        vm.prank(relayer);
        periphery.intentDeposit(dOrder);

        SignedWithdrawIntent memory wOrder =
            signedWithdrawIntent(2, bob, bobPK, address(mockToken2), type(uint256).max, 0, 0, 1);

        vm.prank(relayer);
        periphery.intentWithdraw(wOrder);

        wOrder =
            signedWithdrawIntent(1, alice, alicePK, address(mockToken2), type(uint256).max, 0, 0, 0);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OnlySuperUser.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_only_non_expired_account_can_deposit(uint256 timestamp)
        public
        whitelistUser(alice, 1, Role.USER, false)
        approveAllPeriphery(alice)
    {
        vm.assume(timestamp > 1);
        vm.assume(timestamp < 100000000 * 2);

        vm.warp(timestamp);

        SignedDepositIntent memory dOrder =
            depositIntent(1, alice, alicePK, address(mockToken1), mock1Unit, 0, 0, 0);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountExpired.selector);
        periphery.intentDeposit(dOrder);
    }

    function test_expired_account_can_withdraw()
        public
        whitelistUser(alice, 1000, Role.USER, false)
        approveAllPeriphery(alice)
    {
        SignedDepositIntent memory dOrder =
            depositIntent(1, alice, alicePK, address(mockToken1), mock1Unit, 0, 0, 0);

        vm.prank(relayer);
        periphery.intentDeposit(dOrder);

        assertTrue(periphery.internalVault().balanceOf(alice) > 0);
        assertFalse(periphery.getAccountInfo(1).isExpired());

        vm.warp(100000000 * 2);

        assertTrue(periphery.getAccountInfo(1).isExpired());

        SignedWithdrawIntent memory wOrder =
            signedWithdrawIntent(1, alice, alicePK, address(mockToken1), type(uint256).max, 0, 0, 1);

        vm.prank(relayer);
        periphery.intentWithdraw(wOrder);

        assertTrue(periphery.internalVault().balanceOf(alice) == 0);
    }

    function test_only_allowed_assets_can_be_deposited_or_withdrawn(address asset)
        public
        whitelistUser(alice, 1000000, Role.USER, false)
    {
        vm.assume(asset != address(mockToken1));
        vm.assume(asset != address(mockToken2));

        SignedDepositIntent memory dOrder =
            depositIntent(1, alice, alicePK, asset, mock2Unit, 0, 0, 0);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AssetUnavailable.selector);
        periphery.intentDeposit(dOrder);

        SignedWithdrawIntent memory wOrder =
            signedWithdrawIntent(1, alice, alicePK, asset, mock2Unit, 0, 0, 0);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AssetUnavailable.selector);
        periphery.intentWithdraw(wOrder);
    }

    function test_only_admin_can_pause_unpause_account(address attacker)
        public
        whitelistUser(alice, 1000000, Role.USER, false)
    {
        vm.assume(attacker != address(fund));

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyAdmin.selector);
        periphery.pauseAccount(1);

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyAdmin.selector);
        periphery.unpauseAccount(1);

        vm.prank(address(fund));
        periphery.pauseAccount(1);

        assertTrue(periphery.getAccountInfo(1).state == AccountState.PAUSED);

        vm.prank(address(fund));
        periphery.unpauseAccount(1);

        assertTrue(periphery.getAccountInfo(1).state == AccountState.ACTIVE);
    }

    function test_only_admin_can_close_account(address attacker)
        public
        whitelistUser(alice, 1000000, Role.USER, false)
    {
        vm.assume(attacker != address(fund));

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyAdmin.selector);
        periphery.closeAccount(1);

        vm.prank(address(fund));
        periphery.closeAccount(1);

        assertTrue(periphery.getAccountInfo(1).state == AccountState.CLOSED);
        vm.expectRevert();
        periphery.ownerOf(1);
    }

    function test_only_fund_can_pause_unpause_module(address attacker, address pauser) public {
        vm.assume(attacker != address(fund));
        vm.assume(pauser != address(fund));
        vm.assume(pauser != address(0));
        vm.assume(pauser != attacker);

        vm.prank(address(fund));
        fund.grantRoles(pauser, PAUSER_ROLE);

        vm.prank(attacker);
        vm.expectRevert(Errors.Fund_NotAuthorized.selector);
        fund.pause(address(periphery));

        vm.prank(address(fund));
        fund.pause(address(periphery));

        assertTrue(fund.paused(address(periphery)));

        vm.prank(attacker);
        vm.expectRevert(Errors.Fund_NotAuthorized.selector);
        fund.unpause(address(periphery));

        vm.prank(address(fund));
        fund.unpause(address(periphery));

        assertTrue(!fund.paused(address(periphery)));

        vm.prank(pauser);
        fund.pause(address(periphery));

        assertTrue(fund.paused(address(periphery)));

        vm.prank(pauser);
        fund.unpause(address(periphery));

        assertTrue(!fund.paused(address(periphery)));
    }

    function test_cannot_transfer_souldbound_broker_account(address attacker)
        public
        whitelistUser(alice, 1000000, Role.USER, false)
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
        whitelistUser(alice, 2 days, Role.USER, true)
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

    function test_only_fund_can_change_admin(address attacker) public {
        vm.assume(attacker != address(fund) && attacker != address(0));

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyFund.selector);
        periphery.setAdmin(attacker);

        vm.prank(address(fund));
        periphery.setAdmin(attacker);

        assertTrue(periphery.admin() == attacker);
    }

    function test_only_fund_can_change_protocol_fee_recipient(address attacker) public {
        vm.assume(attacker != address(fund) && attacker != address(0));

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyFund.selector);
        periphery.setProtocolFeeRecipient(attacker);

        vm.prank(address(fund));
        periphery.setProtocolFeeRecipient(attacker);

        assertTrue(periphery.protocolFeeRecipient() == attacker);
    }

    function test_only_fund_can_set_management_fee(address attacker) public {
        vm.assume(attacker != address(fund));

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyFund.selector);
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

        _whitelistUser(broker, 2 days, Role.USER, false);

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
