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
import {TestBaseDeposit} from "./TestBaseDeposit.sol";
import {IPermit2} from "@permit2/src/interfaces/IPermit2.sol";
import "@src/libs/Constants.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract TestDepositModulePermissions is TestBaseDeposit {
    using MessageHashUtils for bytes;
    using DepositLibs for BrokerAccountInfo;

    function setUp() public override(TestBaseDeposit) {
        TestBaseDeposit.setUp();

        vm.prank(address(fund));
        balanceOfOracle.addBalanceToValuate(address(mockToken1), address(fund));
    }

    function test_set_net_deposit_limit(uint256 limit_, address attacker) public {
        vm.assume(limit_ > 0);
        vm.assume(attacker != address(fund));

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, FUND_ROLE
            )
        );
        depositModule.setNetDepositLimit(limit_);

        vm.prank(address(fund));
        depositModule.setNetDepositLimit(limit_);

        vm.prank(address(fund));
        vm.expectRevert(Errors.Deposit_InvalidNetDepositLimit.selector);
        depositModule.setNetDepositLimit(0);
    }

    function test_net_deposit_limit_cannot_be_exceeded(uint256 limit_)
        public
        withRole(alice, DEPOSITOR_ROLE)
        maxApproveDepositModule(alice, address(mockToken1))
    {
        vm.assume(
            limit_ > depositModule.getGlobalAssetPolicy(address(mockToken1)).minimumDeposit + 1
        );
        vm.assume(limit_ < type(uint128).max);

        vm.prank(address(fund));
        depositModule.setNetDepositLimit(limit_);

        mockToken1.mint(alice, type(uint192).max);

        vm.startPrank(alice);
        vm.expectRevert(Errors.Deposit_NetDepositLimitExceeded.selector);
        // deposit max amount
        depositModule.deposit(address(mockToken1), type(uint192).max, 0, alice);
        vm.stopPrank();
    }

    function test_deposit_reverts_when_shares_minted_is_zero()
        public
        withRole(alice, DEPOSITOR_ROLE)
        maxApproveDepositModule(alice, address(mockToken1))
    {
        uint256 smallAmount =
            depositModule.getGlobalAssetPolicy(address(mockToken1)).minimumDeposit + 1;
        mockToken1.mint(alice, smallAmount);

        vm.prank(alice);
        depositModule.deposit(address(mockToken1), smallAmount, 0, alice);

        // We inflate the fund's total assets by minting a large amount of mockToken1
        uint256 largeAmount = type(uint160).max;
        mockToken1.mint(address(fund), largeAmount);

        // Now try to deposit a very small amount
        // this amount is too small to mint any shares
        mockToken1.mint(alice, smallAmount);

        vm.startPrank(alice);
        vm.expectRevert(Errors.Deposit_InsufficientShares.selector);
        depositModule.deposit(address(mockToken1), smallAmount, 0, alice);
        vm.stopPrank();
    }

    function test_only_allowed_assets_can_be_deposited_or_withdrawn(address asset)
        public
        withRole(alice, DEPOSITOR_ROLE)
        withRole(alice, WITHDRAWER_ROLE)
    {
        vm.assume(asset != address(mockToken1));
        vm.assume(asset != address(mockToken2));

        vm.prank(alice);
        vm.expectRevert(Errors.Deposit_AssetUnavailable.selector);
        depositModule.deposit(asset, type(uint256).max, 0, alice);

        vm.prank(alice);
        vm.expectRevert(Errors.Deposit_AssetUnavailable.selector);
        depositModule.withdraw(asset, type(uint256).max, 0, alice);
    }

    function test_only_depositor_role_can_deposit() public {
        assertFalse(depositModule.hasRole(DEPOSITOR_ROLE, alice));

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEPOSITOR_ROLE
            )
        );
        depositModule.deposit(address(mockToken1), type(uint256).max, 0, alice);
    }

    function test_only_withdrawer_role_can_withdraw() public {
        assertFalse(depositModule.hasRole(WITHDRAWER_ROLE, alice));

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, WITHDRAWER_ROLE
            )
        );
        depositModule.withdraw(address(mockToken1), type(uint256).max, 0, alice);
    }

    function test_only_diluter_role_can_dilute_shares() public {
        assertFalse(depositModule.hasRole(DILUTER_ROLE, alice));

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DILUTER_ROLE
            )
        );
        depositModule.dilute(type(uint256).max, alice);
    }

    function test_only_pauser_role_can_pause() public {
        assertFalse(depositModule.hasRole(PAUSER_ROLE, alice));

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, PAUSER_ROLE
            )
        );
        depositModule.pause();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, PAUSER_ROLE
            )
        );
        depositModule.unpause();
    }

    function test_only_fund_role_can_set_pauser() public {
        assertFalse(depositModule.hasRole(FUND_ROLE, alice));

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, FUND_ROLE
            )
        );
        depositModule.setPauser(alice);

        vm.prank(address(fund));
        depositModule.setPauser(alice);

        assertTrue(depositModule.hasRole(PAUSER_ROLE, alice));
    }

    function test_can_only_deposit_when_not_paused() public {
        vm.prank(address(fund));
        depositModule.pause();

        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        depositModule.deposit(address(mockToken1), type(uint256).max, 0, alice);
    }

    function test_can_only_withdraw_when_not_paused() public {
        vm.prank(address(fund));
        depositModule.pause();

        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        depositModule.withdraw(address(mockToken1), type(uint256).max, 0, alice);
    }
}
