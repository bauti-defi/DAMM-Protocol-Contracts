// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity ^0.8.0;

import {TestBasePeriphery, SignedDepositIntent} from "./TestBasePeriphery.sol";
import {IPermit2} from "@permit2/src/interfaces/IPermit2.sol";
import {IPeriphery} from "@src/interfaces/IPeriphery.sol";

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

    function test_deposit(uint256 amount, bool all)
        public
        openAccount(alice, 10000, false, false)
        maxApproveAllPermit2(alice)
    {
        amount = bound(
            amount,
            depositModule.getGlobalAssetPolicy(address(mockToken1)).minimumDeposit,
            type(uint160).max - 1
        );
        uint256 accountId = periphery.peekNextTokenId() - 1;
        _enableBrokerAssetPolicy(accountManager, accountId, address(mockToken1), true);

        mockToken1.mint(alice, amount);

        vm.startPrank(alice);
        uint256 sharesOut = periphery.deposit(
            depositOrder(
                accountId, alice, alice, address(mockToken1), all ? type(uint256).max : amount
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
            type(uint160).max - 1
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

        assertApproxEqAbs(
            mockToken1.balanceOf(address(fund)), 0, precisionLoss, "fund balance wrong"
        );
        assertApproxEqAbs(
            mockToken1.balanceOf(address(periphery)), 0, precisionLoss, "periphery balance wrong"
        );
        assertApproxEqAbs(
            mockToken1.balanceOf(address(alice)),
            withdrawAmount,
            precisionLoss,
            "alice balance wrong"
        );
        assertEq(internalVault.balanceOf(address(alice)), 0, "alice balance wrong");
        assertEq(internalVault.totalSupply(), 0, "internal vault total supply wrong");
        assertEq(internalVault.totalAssets(), 0, "internal vault total assets wrong");
    }

    struct TestDepositIntentFuzz {
        uint256 amount;
        bool all;
        uint256 bribe;
        uint256 relayerTip;
    }

    function boundIntentParams(TestDepositIntentFuzz memory fuzz)
        private
        view
        returns (TestDepositIntentFuzz memory)
    {
        vm.assume(
            fuzz.amount > depositModule.getGlobalAssetPolicy(address(mockToken1)).minimumDeposit
        );
        vm.assume(fuzz.amount < type(uint144).max);

        vm.assume(fuzz.bribe < fuzz.amount / 6);
        vm.assume(fuzz.relayerTip < fuzz.amount / 6);

        return fuzz;
    }

    function test_deposit_intent(TestDepositIntentFuzz memory fuzz)
        public
        openAccount(alice, 10000, false, false)
        maxApproveAllPermit2(alice)
    {
        fuzz = boundIntentParams(fuzz);

        uint256 accountId = periphery.peekNextTokenId() - 1;
        _enableBrokerAssetPolicy(accountManager, accountId, address(mockToken1), true);

        mockToken1.mint(alice, fuzz.amount + fuzz.bribe + fuzz.relayerTip);

        SignedDepositIntent memory intent = depositIntent(
            accountId,
            alice,
            alicePK,
            alice,
            address(mockToken1),
            fuzz.all ? type(uint256).max : fuzz.amount,
            fuzz.relayerTip,
            fuzz.bribe,
            periphery.getAccountNonce(accountId)
        );

        vm.startPrank(relayer);
        uint256 sharesOut = periphery.intentDeposit(intent);
        vm.stopPrank();
        assertEq(
            mockToken1.balanceOf(address(fund)), fuzz.amount + fuzz.bribe, "fund token balance"
        );
        assertEq(mockToken1.balanceOf(address(periphery)), 0, "periphery token balance");
        assertEq(mockToken1.balanceOf(address(relayer)), fuzz.relayerTip, "relayer token balance");
        assertEq(mockToken1.balanceOf(address(alice)), 0, "alice token balance");
        assertEq(internalVault.balanceOf(address(alice)), sharesOut, "alice internal vault balance");
        assertEq(internalVault.balanceOf(address(periphery)), 0, "periphery internal vault balance");
        assertEq(internalVault.totalSupply(), sharesOut, "internal vault total supply");
        assertEq(
            internalVault.totalAssets(), fuzz.amount + fuzz.bribe, "internal vault total assets"
        );
    }

    function deepStack_intentWithdraw(
        TestDepositIntentFuzz memory fuzz,
        uint256 accountId,
        uint256 sharesOut
    ) private returns (uint256 assetOut) {
        vm.startPrank(relayer);
        assetOut = periphery.intentWithdraw(
            signedWithdrawIntent(
                accountId,
                alice,
                alicePK,
                alice,
                address(mockToken1),
                fuzz.all ? type(uint256).max : sharesOut,
                fuzz.relayerTip,
                fuzz.bribe,
                periphery.getAccountNonce(accountId)
            )
        );
        vm.stopPrank();
    }

    function test_withdraw_intent(TestDepositIntentFuzz memory fuzz)
        public
        openAccount(alice, 10000, false, false)
        maxApproveAllPermit2(alice)
    {
        fuzz = boundIntentParams(fuzz);

        uint256 accountId = periphery.peekNextTokenId() - 1;
        _enableBrokerAssetPolicy(accountManager, accountId, address(mockToken1), true);
        _enableBrokerAssetPolicy(accountManager, accountId, address(mockToken1), false);

        mockToken1.mint(alice, fuzz.amount);

        vm.prank(alice);
        uint256 sharesOut = periphery.deposit(
            depositOrder(accountId, alice, alice, address(mockToken1), type(uint256).max)
        );

        // clear balances
        mockToken1.burn(alice, mockToken1.balanceOf(alice));
        mockToken1.burn(relayer, mockToken1.balanceOf(relayer));

        uint256 assetOut = deepStack_intentWithdraw(fuzz, accountId, sharesOut);

        assertApproxEqAbs(
            mockToken1.balanceOf(address(fund)), fuzz.bribe, precisionLoss, "fund token balance"
        );
        assertApproxEqAbs(
            mockToken1.balanceOf(relayer), fuzz.relayerTip, precisionLoss, "fund token balance"
        );
        assertApproxEqAbs(
            mockToken1.balanceOf(address(periphery)), 0, precisionLoss, "periphery token balance"
        );
        assertApproxEqAbs(
            mockToken1.balanceOf(alice) - assetOut, 0, precisionLoss, "alice token balance"
        );
        assertEq(internalVault.balanceOf(address(alice)), 0, "alice internal vault balance");
        assertEq(internalVault.balanceOf(address(periphery)), 0, "periphery internal vault balance");
        assertEq(internalVault.totalSupply(), 0, "internal vault total supply");
        assertEq(internalVault.totalAssets(), 0, "internal vault total assets");
    }

    function test_supports_interface() public view {
        assertTrue(periphery.supportsInterface(type(IPeriphery).interfaceId));
    }
}
