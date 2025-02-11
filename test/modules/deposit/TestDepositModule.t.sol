// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity ^0.8.0;

import {TestBaseDeposit} from "./TestBaseDeposit.sol";
import {AssetPolicy} from "@src/modules/deposit/Structs.sol";
import {IDepositModule} from "@src/interfaces/IDepositModule.sol";
import "@src/libs/Constants.sol";

contract TestDepositModule is TestBaseDeposit {
    function setUp() public override(TestBaseDeposit) {
        TestBaseDeposit.setUp();

        vm.startPrank(address(fund));
        balanceOfOracle.addBalanceToValuate(address(mockToken1), address(fund));
        balanceOfOracle.addBalanceToValuate(address(mockToken2), address(fund));
        vm.stopPrank();
    }

    function test_deposit(uint256 amount)
        public
        withRole(alice, CONTROLLER_ROLE)
        maxApproveDepositModule(alice, address(mockToken1))
    {
        amount = bound(
            amount,
            depositModule.getGlobalAssetPolicy(address(mockToken1)).minimumDeposit + 1,
            type(uint192).max
        );
        mockToken1.mint(alice, amount);

        vm.startPrank(alice);
        depositModule.deposit(address(mockToken1), amount, 0, alice);
        vm.stopPrank();

        assertEq(mockToken1.balanceOf(address(fund)), amount);
        assertEq(mockToken1.balanceOf(address(alice)), 0);
        assertEq(internalVault.totalAssets(), amount);
        assertEq(internalVault.totalSupply(), internalVault.balanceOf(alice));
    }

    function test_withdraw(uint256 amount)
        public
        withRole(alice, CONTROLLER_ROLE)
        maxApproveDepositModule(alice, address(mockToken1))
        maxApproveDepositModule(alice, address(internalVault))
    {
        amount = bound(
            amount,
            depositModule.getGlobalAssetPolicy(address(mockToken1)).minimumWithdrawal + 1,
            type(uint192).max
        );
        mockToken1.mint(alice, amount);

        vm.prank(alice);
        depositModule.deposit(address(mockToken1), amount, 0, alice);

        vm.startPrank(alice);
        depositModule.withdraw(address(mockToken1), internalVault.balanceOf(alice), 0, alice);
        vm.stopPrank();

        assertEq(mockToken1.balanceOf(alice), amount);
        assertEq(mockToken1.balanceOf(address(fund)), 0);
        assertEq(internalVault.totalAssets(), 0);
        assertEq(internalVault.totalSupply(), 0);
    }

    function test_dilute(uint256 amount) public withRole(alice, CONTROLLER_ROLE) {
        amount = bound(amount, 1, type(uint256).max);

        vm.prank(alice);
        depositModule.dilute(amount, alice);

        assertEq(internalVault.totalAssets(), 0);
        assertEq(internalVault.totalSupply(), amount);
    }

    function test_enable_global_asset_policy(AssetPolicy memory policy, address asset) public {
        vm.assume(asset != address(0));
        vm.assume(asset != address(mockToken1));
        vm.assume(asset != address(mockToken2));

        assertFalse(depositModule.getGlobalAssetPolicy(asset).enabled);

        policy.enabled = true;

        vm.prank(address(fund));
        depositModule.enableGlobalAssetPolicy(asset, policy);

        assertTrue(depositModule.getGlobalAssetPolicy(asset).enabled);
        assertEq(depositModule.getGlobalAssetPolicy(asset).minimumDeposit, policy.minimumDeposit);
        assertEq(
            depositModule.getGlobalAssetPolicy(asset).minimumWithdrawal, policy.minimumWithdrawal
        );
        assertEq(depositModule.getGlobalAssetPolicy(asset).canDeposit, policy.canDeposit);
        assertEq(depositModule.getGlobalAssetPolicy(asset).canWithdraw, policy.canWithdraw);
    }

    function test_disable_global_asset_policy() public {
        assertTrue(depositModule.getGlobalAssetPolicy(address(mockToken1)).enabled);

        vm.prank(address(fund));
        depositModule.disableGlobalAssetPolicy(address(mockToken1));

        assertFalse(depositModule.getGlobalAssetPolicy(address(mockToken1)).enabled);
    }

    function test_upsert_global_asset_policy(
        AssetPolicy memory policy1,
        AssetPolicy memory policy2,
        address asset
    ) public {
        vm.assume(asset != address(0));
        vm.assume(asset != address(mockToken1));
        vm.assume(asset != address(mockToken2));

        policy1.enabled = true;
        policy2.enabled = true;

        vm.prank(address(fund));
        depositModule.enableGlobalAssetPolicy(asset, policy1);

        assertTrue(depositModule.getGlobalAssetPolicy(asset).enabled);
        assertEq(depositModule.getGlobalAssetPolicy(asset).minimumDeposit, policy1.minimumDeposit);
        assertEq(
            depositModule.getGlobalAssetPolicy(asset).minimumWithdrawal, policy1.minimumWithdrawal
        );
        assertEq(depositModule.getGlobalAssetPolicy(asset).canDeposit, policy1.canDeposit);
        assertEq(depositModule.getGlobalAssetPolicy(asset).canWithdraw, policy1.canWithdraw);

        vm.prank(address(fund));
        depositModule.enableGlobalAssetPolicy(asset, policy2);

        assertTrue(depositModule.getGlobalAssetPolicy(asset).enabled);
        assertEq(depositModule.getGlobalAssetPolicy(asset).minimumDeposit, policy2.minimumDeposit);
        assertEq(
            depositModule.getGlobalAssetPolicy(asset).minimumWithdrawal, policy2.minimumWithdrawal
        );
        assertEq(depositModule.getGlobalAssetPolicy(asset).canDeposit, policy2.canDeposit);
        assertEq(depositModule.getGlobalAssetPolicy(asset).canWithdraw, policy2.canWithdraw);
    }

    function test_pause() public {
        assertFalse(depositModule.paused());

        vm.prank(address(fund));
        depositModule.pause();

        assertTrue(depositModule.paused());

        vm.prank(address(fund));
        depositModule.unpause();

        assertFalse(depositModule.paused());
    }

    function test_set_pauser() public {
        assertFalse(depositModule.hasRole(PAUSER_ROLE, alice));

        vm.prank(address(fund));
        depositModule.setPauser(alice);

        assertTrue(depositModule.hasRole(PAUSER_ROLE, alice));
    }

    function test_revoke_pauser() public {
        assertFalse(depositModule.hasRole(PAUSER_ROLE, alice));

        vm.prank(address(fund));
        depositModule.setPauser(alice);

        assertTrue(depositModule.hasRole(PAUSER_ROLE, alice));

        vm.prank(address(fund));
        depositModule.revokePauser(alice);

        assertFalse(depositModule.hasRole(PAUSER_ROLE, alice));
    }

    function test_supports_interface() public {
        assertTrue(depositModule.supportsInterface(type(IDepositModule).interfaceId));
    }
}
