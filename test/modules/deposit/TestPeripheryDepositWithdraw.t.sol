// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity ^0.8.0;

import {TestBasePeriphery} from "./TestBasePeriphery.sol";
import {IPermit2} from "@permit2/src/interfaces/IPermit2.sol";

contract TestPeripheryDepositWithdraw is TestBasePeriphery {
    function setUp() public override(TestBasePeriphery) {
        TestBasePeriphery.setUp();

        vm.prank(address(fund));
        balanceOfOracle.addBalanceToValuate(address(mockToken1), address(fund));

        vm.startPrank(alice);
        IPermit2(permit2).approve(
            address(internalVault), address(periphery), type(uint160).max, type(uint48).max
        );
        IPermit2(permit2).approve(
            address(mockToken1), address(periphery), type(uint160).max, type(uint48).max
        );
        vm.stopPrank();
    }

    function test_deposit(uint256 amount, bool depositAll)
        public
        openAccount(alice, 10000, false, false)
        maxApproveAllPermit2(alice)
    {
        amount = bound(
            amount,
            depositModule.getGlobalAssetPolicy(address(mockToken1)).minimumDeposit,
            type(uint160).max
        );
        uint256 accountId = periphery.peekNextTokenId() - 1;
        _enableBrokerAssetPolicy(accountManager, accountId, address(mockToken1), true);

        mockToken1.mint(alice, amount);

        vm.startPrank(alice);
        uint256 sharesOut = periphery.deposit(
            depositOrder(
                accountId,
                alice,
                alice,
                address(mockToken1),
                depositAll ? type(uint256).max : amount
            )
        );
        vm.stopPrank();

        assertEq(mockToken1.balanceOf(address(fund)), amount);
        assertEq(mockToken1.balanceOf(address(periphery)), 0);
        assertEq(mockToken1.balanceOf(address(alice)), 0);
        assertEq(internalVault.balanceOf(address(alice)), sharesOut);
        assertEq(internalVault.totalSupply(), sharesOut);
        assertEq(internalVault.totalAssets(), amount);
    }

    function test_withdraw(uint256 depositAmount, bool withdrawAll)
        public
        openAccount(alice, 10000, false, false)
        maxApproveAllPermit2(alice)
    {
        depositAmount = bound(
            depositAmount,
            depositModule.getGlobalAssetPolicy(address(mockToken1)).minimumDeposit,
            type(uint160).max
        );
        uint256 accountId = periphery.peekNextTokenId() - 1;
        _enableBrokerAssetPolicy(accountManager, accountId, address(mockToken1), true);
        _enableBrokerAssetPolicy(accountManager, accountId, address(mockToken1), false);

        mockToken1.mint(alice, depositAmount);

        vm.startPrank(alice);
        uint256 sharesOut = periphery.deposit(
            depositOrder(accountId, alice, alice, address(mockToken1), depositAmount)
        );
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 withdrawAmount = periphery.withdraw(
            withdrawOrder(
                accountId,
                alice,
                alice,
                address(mockToken1),
                withdrawAll ? type(uint256).max : sharesOut
            )
        );
        vm.stopPrank();

        assertEq(mockToken1.balanceOf(address(fund)), 0);
        assertEq(mockToken1.balanceOf(address(periphery)), 0);
        assertEq(mockToken1.balanceOf(address(alice)), withdrawAmount);
        assertEq(internalVault.balanceOf(address(alice)), 0);
        assertEq(internalVault.totalSupply(), 0);
        assertEq(internalVault.totalAssets(), 0);
    }
}
