// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {
    CurveCallValidator,
    CurveCallValidator_InvalidAssetPool
} from "@src/hooks/curve/CurveCallValidator.sol";
import {ICurvePool} from "@src/interfaces/external/ICurvePool.sol";
import {IBeforeTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {Errors} from "@src/libs/Errors.sol";
import "@src/libs/Constants.sol";

contract TestCurveHooks is Test {
    event CurveCallValidator_AssetPoolEnabled(address pool, int128 i, int128 j);
    event CurveCallValidator_AssetPoolDisabled(address pool, int128 i, int128 j);

    CurveCallValidator validator;

    function setUp() public {
        address fund = makeAddr("fund");
        vm.prank(fund);
        validator = new CurveCallValidator(fund);
    }

    function test_enable_disable_asset_pool(address fund, address pool, int128 i, int128 j)
        public
    {
        vm.assume(fund != address(0));
        vm.assume(pool != address(0));

        validator = new CurveCallValidator(fund);

        vm.prank(fund);
        vm.expectEmit(true, true, true, true);
        emit CurveCallValidator_AssetPoolEnabled(pool, i, j);
        validator.enableAssetPool(pool, i, j);

        bytes32 pointer = keccak256(abi.encodePacked(pool, i, j));
        assertTrue(validator.assetPoolWhitelist(pointer), "Asset pool not whitelisted");

        vm.prank(fund);
        vm.expectEmit(true, true, true, true);
        emit CurveCallValidator_AssetPoolDisabled(pool, i, j);
        validator.disableAssetPool(pool, i, j);

        assertFalse(validator.assetPoolWhitelist(pointer), "Asset pool still whitelisted");
    }

    function test_only_fund_can_enable_asset_pool(
        address fund,
        address pool,
        address attacker,
        int128 i,
        int128 j
    ) public {
        vm.assume(fund != address(0));
        vm.assume(pool != address(0));
        vm.assume(attacker != fund);

        validator = new CurveCallValidator(fund);

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyFund.selector);
        validator.enableAssetPool(pool, i, j);
    }

    function test_only_fund_can_disable_asset_pool(
        address fund,
        address pool,
        address attacker,
        int128 i,
        int128 j
    ) public {
        vm.assume(fund != address(0));
        vm.assume(pool != address(0));
        vm.assume(attacker != fund);

        validator = new CurveCallValidator(fund);

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyFund.selector);
        validator.disableAssetPool(pool, i, j);
    }

    function test_check_before_transaction(
        address fund,
        address pool,
        int128 i,
        int128 j,
        uint256 amount
    ) public {
        vm.assume(fund != address(0));
        vm.assume(pool != address(0));
        vm.assume(amount > 0);

        validator = new CurveCallValidator(fund);

        // Enable the pool first
        vm.prank(fund);
        validator.enableAssetPool(pool, i, j);

        // Prepare the exchange call data
        bytes memory data = abi.encode(i, j, amount, 0);

        vm.prank(fund);
        validator.checkBeforeTransaction(pool, ICurvePool.exchange.selector, CALL, 0, data);
    }

    function test_check_before_transaction_reverts_for_disabled_pool(
        address fund,
        address pool,
        int128 i,
        int128 j,
        uint256 amount
    ) public {
        vm.assume(fund != address(0));
        vm.assume(pool != address(0));
        vm.assume(amount > 0);

        validator = new CurveCallValidator(fund);
        bytes memory data = abi.encode(i, j, amount, 0);

        vm.prank(fund);
        vm.expectRevert(CurveCallValidator_InvalidAssetPool.selector);
        validator.checkBeforeTransaction(pool, ICurvePool.exchange.selector, CALL, 0, data);
    }

    function test_check_before_transaction_reverts_for_invalid_selector(
        address fund,
        address pool,
        bytes4 invalidSelector,
        int128 i,
        int128 j,
        uint256 amount
    ) public {
        vm.assume(fund != address(0));
        vm.assume(pool != address(0));
        vm.assume(invalidSelector != ICurvePool.exchange.selector);
        vm.assume(amount > 0);

        validator = new CurveCallValidator(fund);
        bytes memory data = abi.encode(i, j, amount, 0);

        vm.prank(fund);
        vm.expectRevert(Errors.Hook_InvalidTargetSelector.selector);
        validator.checkBeforeTransaction(pool, invalidSelector, CALL, 0, data);
    }

    function test_supports_interface() public {
        address fund = makeAddr("fund");
        validator = new CurveCallValidator(fund);

        assertTrue(
            validator.supportsInterface(type(IBeforeTransaction).interfaceId),
            "Should support IBeforeTransaction interface"
        );
    }
}
