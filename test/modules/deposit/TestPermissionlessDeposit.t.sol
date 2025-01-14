// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TestBaseDeposit, MINIMUM_DEPOSIT} from "./TestBaseDeposit.sol";
import {PermissionlessDepositModule} from "@src/modules/deposit/PermissionlessDepositModule.sol";
import {CreateAccountParams, Role} from "@src/modules/deposit/Structs.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {Errors} from "@src/libs/Errors.sol";

uint256 constant RELAYER_TIP = 10;
uint256 constant BRIBE = 10;

contract TestPermissionlessDeposit is TestBaseDeposit {
    SafeL2 internal safe;
    PermissionlessDepositModule internal permissionlessDepositModule;
    uint256 internal accountId;

    function setUp() public override(TestBaseDeposit) {
        TestBaseDeposit.setUp();

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;
        safe = deploySafe(admins, 1);
        vm.label(address(safe), "Holding Safe");

        permissionlessDepositModule = PermissionlessDepositModule(
            deployModule(
                payable(address(safe)),
                fundAdmin,
                fundAdminPK,
                bytes32("permissionlessDepositModule"),
                0,
                abi.encodePacked(
                    type(PermissionlessDepositModule).creationCode,
                    abi.encode(address(safe), address(periphery))
                )
            )
        );
        vm.label(address(permissionlessDepositModule), "Permissionless Deposit Module");

        /// mint broker nft to safe, make unlimited
        vm.startPrank(address(fund));
        accountId = periphery.openAccount(
            CreateAccountParams({
                ttl: type(uint256).max - block.timestamp,
                shareMintLimit: type(uint256).max,
                brokerPerformanceFeeInBps: 0,
                protocolPerformanceFeeInBps: 0,
                brokerEntranceFeeInBps: 0,
                protocolEntranceFeeInBps: 0,
                brokerExitFeeInBps: 0,
                protocolExitFeeInBps: 0,
                feeRecipient: feeRecipient,
                user: address(safe),
                transferable: false,
                role: Role.USER
            })
        );
        vm.stopPrank();
    }

    modifier approveAllModule(address user) {
        vm.startPrank(user);
        mockToken1.approve(address(permissionlessDepositModule), type(uint256).max);
        mockToken2.approve(address(permissionlessDepositModule), type(uint256).max);
        periphery.internalVault().approve(address(permissionlessDepositModule), type(uint256).max);
        vm.stopPrank();

        _;
    }

    /// @notice if the bribe is greater than the deposit amount then we risk minting 0 shares
    function test_deposit_must_mint_more_than_zero_shares(uint128 _amount, uint128 _bribe)
        public
        approveAllPeriphery(address(safe))
        approveAllModule(alice)
    {
        uint256 amount = uint256(_amount);
        uint256 bribe = uint256(_bribe);

        vm.assume(bribe > amount ** 2);
        vm.assume(amount > MINIMUM_DEPOSIT);

        mockToken1.mint(alice, amount + bribe);

        uint256 nonce = permissionlessDepositModule.nonces(alice);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InsufficientShares.selector);
        permissionlessDepositModule.intentDeposit(
            _depositIntent(accountId, alice, alicePK, address(mockToken1), amount, 0, bribe, nonce)
        );
    }

    function test_deposit_withdraw(uint128 _amount, bool intent, bool relayerTip, bool bribe)
        public
        approveAllPeriphery(address(safe))
        approveAllModule(alice)
    {
        vm.assume(_amount > MINIMUM_DEPOSIT);
        uint256 amount = uint256(_amount);
        mockToken1.mint(alice, amount);

        /// simple deposit on behalf of alice
        uint256 sharesOut;
        if (intent) {
            if (relayerTip) mockToken1.mint(alice, RELAYER_TIP);
            if (bribe) mockToken1.mint(alice, BRIBE);

            uint256 nonce = permissionlessDepositModule.nonces(alice);

            vm.prank(relayer);
            sharesOut = permissionlessDepositModule.intentDeposit(
                _depositIntent(
                    accountId,
                    alice,
                    alicePK,
                    address(mockToken1),
                    amount,
                    relayerTip ? RELAYER_TIP : 0,
                    bribe ? BRIBE : 0,
                    nonce
                )
            );
            assertEq(
                mockToken1.balanceOf(address(fund)),
                amount + (bribe ? BRIBE : 0),
                "MockToken1 balance should be amount for fund"
            );
            assertEq(
                mockToken1.balanceOf(relayer),
                relayerTip ? RELAYER_TIP : 0,
                "MockToken1 balance should be for relayer"
            );
        } else {
            vm.prank(alice);
            sharesOut = permissionlessDepositModule.deposit(
                _depositOrder(accountId, alice, address(mockToken1), amount)
            );
            assertEq(
                mockToken1.balanceOf(address(fund)),
                amount,
                "MockToken1 balance should be amount for fund"
            );
            assertEq(mockToken1.balanceOf(relayer), 0, "MockToken1 balance should be for relayer");
        }

        assertGt(sharesOut, 0, "Shares out should be greater than 0 for alice");
        assertEq(
            periphery.internalVault().balanceOf(alice),
            sharesOut,
            "Shares out should be equal to sharesOut"
        );
        assertEq(
            periphery.internalVault().balanceOf(address(fund)), 0, "Fund shares balance should be 0"
        );
        assertEq(
            periphery.internalVault().balanceOf(address(safe)), 0, "Safe shares balance should be 0"
        );
        assertEq(mockToken1.balanceOf(alice), 0, "MockToken1 balance should be 0 for alice");
        assertEq(mockToken1.balanceOf(address(safe)), 0, "MockToken1 balance should be 0 for safe");

        if (intent) {
            uint256 nonce = permissionlessDepositModule.nonces(alice);
            if (relayerTip) mockToken1.mint(alice, RELAYER_TIP);
            if (bribe) mockToken1.mint(alice, BRIBE);

            vm.prank(relayer);
            permissionlessDepositModule.intentWithdraw(
                _withdrawIntent(
                    accountId,
                    alicePK,
                    alice,
                    address(mockToken1),
                    sharesOut,
                    relayerTip ? RELAYER_TIP : 0,
                    bribe ? BRIBE : 0,
                    nonce
                )
            );

            assertApproxEqRel(
                mockToken1.balanceOf(address(fund)),
                2 * (bribe ? BRIBE : 0),
                0.1e18,
                "MockToken1 balance should be amount for fund"
            );
            assertEq(
                mockToken1.balanceOf(relayer),
                2 * (relayerTip ? RELAYER_TIP : 0),
                "MockToken1 balance should be for relayer"
            );
        } else {
            vm.prank(alice);
            permissionlessDepositModule.withdraw(
                _withdrawOrder(accountId, alice, address(mockToken1), sharesOut)
            );
            assertEq(
                mockToken1.balanceOf(address(fund)),
                0,
                "MockToken1 balance should be amount for fund"
            );
            assertEq(mockToken1.balanceOf(relayer), 0, "MockToken1 balance should be for relayer");
        }

        assertApproxEqRel(
            mockToken1.balanceOf(alice),
            amount,
            0.1e18,
            "MockToken1 balance should be amount for alice"
        );
        assertEq(mockToken1.balanceOf(address(safe)), 0, "MockToken1 balance should be 0 for safe");
        assertEq(
            periphery.internalVault().balanceOf(alice), 0, "Shares balance should be 0 for alice"
        );
        assertEq(
            periphery.internalVault().balanceOf(address(fund)),
            0,
            "Shares balance should be 0 for fund"
        );
        assertEq(
            periphery.internalVault().balanceOf(address(safe)),
            0,
            "Shares balance should be 0 for safe"
        );
    }

    function test_deposit_withdraw_all(uint128 _amount, bool intent, bool relayerTip, bool bribe)
        public
        approveAllPeriphery(address(safe))
        approveAllModule(alice)
    {
        vm.assume(_amount > MINIMUM_DEPOSIT);
        uint256 amount = uint256(_amount);
        mockToken1.mint(alice, amount);

        uint256 sharesOut;
        if (intent) {
            uint256 nonce = permissionlessDepositModule.nonces(alice);
            if (relayerTip) mockToken1.mint(alice, RELAYER_TIP);
            if (bribe) mockToken1.mint(alice, BRIBE);

            vm.prank(relayer);
            sharesOut = permissionlessDepositModule.intentDeposit(
                _depositIntent(
                    accountId,
                    alice,
                    alicePK,
                    address(mockToken1),
                    type(uint256).max,
                    relayerTip ? RELAYER_TIP : 0,
                    bribe ? BRIBE : 0,
                    nonce
                )
            );
            assertEq(
                mockToken1.balanceOf(address(fund)),
                amount + (bribe ? BRIBE : 0),
                "MockToken1 balance should be amount for fund"
            );
            assertEq(
                mockToken1.balanceOf(relayer),
                relayerTip ? RELAYER_TIP : 0,
                "MockToken1 balance should be for relayer"
            );
        } else {
            vm.prank(alice);
            sharesOut = permissionlessDepositModule.deposit(
                _depositOrder(accountId, alice, address(mockToken1), type(uint256).max)
            );

            assertEq(
                mockToken1.balanceOf(address(fund)),
                amount,
                "MockToken1 balance should be amount for fund"
            );
            assertEq(mockToken1.balanceOf(relayer), 0, "MockToken1 balance should be for relayer");
        }

        assertGt(sharesOut, 0, "Shares out should be greater than 0 for alice");
        assertEq(
            periphery.internalVault().balanceOf(alice),
            sharesOut,
            "Shares out should be equal to sharesOut"
        );
        assertEq(
            periphery.internalVault().balanceOf(address(fund)), 0, "Fund shares balance should be 0"
        );
        assertEq(
            periphery.internalVault().balanceOf(address(safe)), 0, "Safe shares balance should be 0"
        );
        assertEq(mockToken1.balanceOf(alice), 0, "MockToken1 balance should be 0 for alice");
        assertEq(mockToken1.balanceOf(address(safe)), 0, "MockToken1 balance should be 0 for safe");

        if (intent) {
            uint256 nonce = permissionlessDepositModule.nonces(alice);
            if (relayerTip) mockToken1.mint(alice, RELAYER_TIP);
            if (bribe) mockToken1.mint(alice, BRIBE);

            vm.startPrank(relayer);
            permissionlessDepositModule.intentWithdraw(
                _withdrawIntent(
                    accountId,
                    alicePK,
                    alice,
                    address(mockToken1),
                    type(uint256).max,
                    relayerTip ? RELAYER_TIP : 0,
                    bribe ? BRIBE : 0,
                    nonce
                )
            );
            vm.stopPrank();
            assertApproxEqRel(
                mockToken1.balanceOf(address(fund)),
                bribe ? 2 * BRIBE : 0,
                0.1e18,
                "MockToken1 balance should be amount for fund"
            );
            assertEq(
                mockToken1.balanceOf(relayer),
                2 * (relayerTip ? RELAYER_TIP : 0),
                "MockToken1 balance should be for relayer"
            );
        } else {
            vm.prank(alice);
            permissionlessDepositModule.withdraw(
                _withdrawOrder(accountId, alice, address(mockToken1), type(uint256).max)
            );
            assertEq(
                mockToken1.balanceOf(address(fund)),
                0,
                "MockToken1 balance should be amount for fund"
            );
            assertEq(mockToken1.balanceOf(relayer), 0, "MockToken1 balance should be for relayer");
        }

        assertApproxEqRel(
            mockToken1.balanceOf(alice),
            amount,
            0.1e18,
            "MockToken1 balance should be amount for alice"
        );
        assertEq(mockToken1.balanceOf(address(safe)), 0, "MockToken1 balance should be 0 for safe");
        assertEq(
            periphery.internalVault().balanceOf(alice), 0, "Shares balance should be 0 for alice"
        );
        assertEq(
            periphery.internalVault().balanceOf(address(fund)),
            0,
            "Shares balance should be 0 for fund"
        );
        assertEq(
            periphery.internalVault().balanceOf(address(safe)),
            0,
            "Shares balance should be 0 for safe"
        );
    }

    function test_only_admin_can_pause_and_unpause() public {
        vm.expectRevert(Errors.OnlyAdmin.selector);
        permissionlessDepositModule.pause();

        vm.expectRevert(Errors.OnlyAdmin.selector);
        permissionlessDepositModule.unpause();

        vm.prank(address(safe));
        permissionlessDepositModule.pause();

        assertEq(permissionlessDepositModule.paused(), true, "Module should be paused");

        vm.prank(address(safe));
        permissionlessDepositModule.unpause();

        assertEq(permissionlessDepositModule.paused(), false, "Module should be unpaused");
    }

    function test_increase_nonce(uint256 increment) public {
        vm.assume(increment > 0);

        uint256 nonce = permissionlessDepositModule.nonces(alice);

        vm.prank(alice);
        permissionlessDepositModule.increaseNonce(increment);

        assertEq(
            permissionlessDepositModule.nonces(alice),
            nonce + increment,
            "Nonce should be incremented"
        );
    }

    function test_can_only_deposit_and_withdraw_if_not_paused(bool intent)
        public
        approveAllPeriphery(address(safe))
        approveAllModule(alice)
    {
        vm.startPrank(address(safe));
        permissionlessDepositModule.pause();
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 sharesOut;
        if (intent) {
            uint256 nonce = permissionlessDepositModule.nonces(alice);
            vm.expectRevert(Errors.Deposit_ModulePaused.selector);
            sharesOut = permissionlessDepositModule.intentDeposit(
                _depositIntent(
                    accountId, alice, alicePK, address(mockToken1), type(uint256).max, 0, 0, nonce
                )
            );
        } else {
            vm.expectRevert(Errors.Deposit_ModulePaused.selector);
            sharesOut = permissionlessDepositModule.deposit(
                _depositOrder(accountId, alice, address(mockToken1), type(uint256).max)
            );
        }
        vm.stopPrank();

        vm.startPrank(alice);
        if (intent) {
            uint256 nonce = permissionlessDepositModule.nonces(alice);
            vm.expectRevert(Errors.Deposit_ModulePaused.selector);
            permissionlessDepositModule.intentWithdraw(
                _withdrawIntent(
                    accountId, alicePK, alice, address(mockToken1), type(uint256).max, 0, 0, nonce
                )
            );
        } else {
            vm.expectRevert(Errors.Deposit_ModulePaused.selector);
            permissionlessDepositModule.withdraw(
                _withdrawOrder(accountId, alice, address(mockToken1), type(uint256).max)
            );
        }
        vm.stopPrank();
    }
}
