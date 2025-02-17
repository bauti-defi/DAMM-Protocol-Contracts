// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity ^0.8.0;

import {TestBasePeriphery} from "./TestBasePeriphery.sol";

contract TestSharedBrokerage is TestBasePeriphery {
    uint256 sharedAccountId;

    function setUp() public override(TestBasePeriphery) {
        TestBasePeriphery.setUp();

        vm.prank(address(fund));
        balanceOfOracle.addBalanceToValuate(address(mockToken1), address(fund));

        sharedAccountId = _openAccount(alice, 100000, false, true);

        _enableBrokerAssetPolicy(accountManager, sharedAccountId, address(mockToken1), true);
        _enableBrokerAssetPolicy(accountManager, sharedAccountId, address(mockToken1), false);
    }

    modifier validUser(address user) {
        _validUser(user);
        _;
    }

    function _validUser(address user) internal {
        vm.assume(user != address(0));
        vm.assume(user != address(fund));
        vm.assume(user != address(periphery));
        vm.assume(user != alice);
        vm.assume(user != bob);
        vm.assume(user != accountManager);
        vm.label(user, "User");
    }

    function test_deposit(address user) public validUser(user) maxApproveAllPermit2(user) {
        mockToken1.mint(user, 100_000_000 * mock1Unit);

        vm.prank(user);
        periphery.deposit(
            depositOrder(sharedAccountId, user, user, address(mockToken1), type(uint256).max)
        );

        assertEq(mockToken1.balanceOf(user), 0);
        assertEq(mockToken1.balanceOf(address(fund)), 100_000_000 * mock1Unit);
        assertEq(mockToken1.balanceOf(address(periphery)), 0);
        assertEq(internalVault.balanceOf(user), internalVault.totalSupply());
    }

    function test_withdraw(address user) public validUser(user) maxApproveAllPermit2(user) {
        mockToken1.mint(user, 100_000_000 * mock1Unit);

        vm.prank(user);
        periphery.deposit(
            depositOrder(sharedAccountId, user, user, address(mockToken1), type(uint256).max)
        );

        assertEq(mockToken1.balanceOf(user), 0);
        assertEq(mockToken1.balanceOf(address(fund)), 100_000_000 * mock1Unit);
        assertEq(mockToken1.balanceOf(address(periphery)), 0);
        assertEq(internalVault.balanceOf(user), internalVault.totalSupply());

        vm.prank(user);
        periphery.withdraw(
            withdrawOrder(sharedAccountId, user, user, address(mockToken1), type(uint256).max)
        );

        assertEq(mockToken1.balanceOf(user), 100_000_000 * mock1Unit);
        assertEq(mockToken1.balanceOf(address(fund)), 0);
        assertEq(mockToken1.balanceOf(address(periphery)), 0);
        assertEq(internalVault.balanceOf(user), 0);
    }

    function test_deposit_intent(uint64 userPK) public {
        vm.assume(userPK != 0);
        address user = vm.addr(uint256(userPK));
        _validUser(user);
        _maxApproveAllPermit2(user);

        mockToken1.mint(user, 100_000_000 * mock1Unit);

        vm.prank(user);
        periphery.intentDeposit(
            signedDepositIntent(
                sharedAccountId, user, userPK, user, address(mockToken1), type(uint256).max, 0, 0, 0
            )
        );

        assertEq(mockToken1.balanceOf(user), 0);
        assertEq(mockToken1.balanceOf(address(fund)), 100_000_000 * mock1Unit);
        assertEq(mockToken1.balanceOf(address(periphery)), 0);
        assertEq(internalVault.balanceOf(user), internalVault.totalSupply());
    }

    function test_withdraw_intent(uint64 userPK) public {
        vm.assume(userPK != 0);
        address user = vm.addr(uint256(userPK));
        _validUser(user);
        _maxApproveAllPermit2(user);

        mockToken1.mint(user, 100_000_000 * mock1Unit);

        vm.prank(user);
        periphery.intentDeposit(
            signedDepositIntent(
                sharedAccountId, user, userPK, user, address(mockToken1), type(uint256).max, 0, 0, 0
            )
        );

        assertEq(mockToken1.balanceOf(user), 0);
        assertEq(mockToken1.balanceOf(address(fund)), 100_000_000 * mock1Unit);
        assertEq(mockToken1.balanceOf(address(periphery)), 0);
        assertEq(internalVault.balanceOf(user), internalVault.totalSupply());

        vm.prank(user);
        periphery.intentWithdraw(
            signedWithdrawIntent(
                sharedAccountId, user, userPK, user, address(mockToken1), type(uint256).max, 0, 0, 1
            )
        );

        assertEq(mockToken1.balanceOf(user), 100_000_000 * mock1Unit);
        assertEq(mockToken1.balanceOf(address(fund)), 0);
        assertEq(mockToken1.balanceOf(address(periphery)), 0);
        assertEq(internalVault.balanceOf(user), 0);
    }
}
