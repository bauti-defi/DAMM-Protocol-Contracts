// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {Test} from "@forge-std/Test.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {LibMulticaller} from "@vec-multicaller/LibMulticaller.sol";
import {IVaultRouterModule} from "@src/interfaces/IVaultRouterModule.sol";

contract MockRouter {
    function fun1() external payable returns (address, uint256, uint256) {
        return (LibMulticaller.sender(), 1, msg.value);
    }

    function fun2() external payable returns (address, uint256, uint256) {
        return (LibMulticaller.sender(), 2, msg.value);
    }

    function shouldRevert1() external pure {
        revert("should revert 1");
    }
}

contract TestVaultRouterModule is TestBaseProtocol {
    address public operator;
    MockRouter public mockRouter;

    address vaultOwner;
    address vault;

    function setUp() public override {
        super.setUp();

        vaultOwner = makeAddr("VaultOwner");
        operator = makeAddr("Operator");

        vault = deployVault(vaultOwner);

        vm.prank(vault);
        dammModule.setOperator(operator, true);

        mockRouter = new MockRouter();
        vm.label(address(mockRouter), "MockRouter");

        vm.prank(vault);
        routerWhitelistRegistry.whitelistRouter(address(mockRouter));

        vm.deal(vault, 1 ether);
    }

    function test_only_operator_can_execute(address _op) public {
        vm.assume(_op != operator);
        vm.expectRevert(IVaultRouterModule.OnlyOperator.selector);
        vm.prank(_op);
        dammModule.execute(
            vault, address(mockRouter), 0, abi.encodeWithSelector(mockRouter.fun1.selector)
        );
    }

    function test_only_operator_can_execute_multicall(address _op) public {
        vm.assume(_op != operator);
        vm.expectRevert(IVaultRouterModule.OnlyOperator.selector);
        vm.prank(_op);
        dammModule.executeMulticall(vault, new address[](0), new bytes[](0), new uint256[](0));
    }

    function test_can_only_execute_when_not_suspended() public {
        vm.prank(vault);
        dammModule.suspendTrading();
        vm.expectRevert(IVaultRouterModule.TradingSuspended.selector);
        dammModule.execute(
            vault, address(mockRouter), 0, abi.encodeWithSelector(mockRouter.fun1.selector)
        );

        vm.prank(vault);
        dammModule.resumeTrading();
        vm.prank(operator);
        dammModule.execute(
            vault, address(mockRouter), 0, abi.encodeWithSelector(mockRouter.fun1.selector)
        );
    }

    function test_can_only_execute_multicall_when_not_suspended() public {
        vm.prank(vault);
        dammModule.suspendTrading();
        vm.expectRevert(IVaultRouterModule.TradingSuspended.selector);
        dammModule.executeMulticall(vault, new address[](0), new bytes[](0), new uint256[](0));

        vm.prank(vault);
        dammModule.resumeTrading();

        address[] memory targets = new address[](1);
        targets[0] = address(mockRouter);

        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSelector(mockRouter.fun1.selector);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.prank(operator);
        bytes[] memory results = dammModule.executeMulticall(vault, targets, datas, values);

        (address caller1, uint256 res1, uint256 value1) =
            abi.decode(results[0], (address, uint256, uint256));

        assertEq(1, res1);
        assertEq(0, value1);
        assertEq(vault, caller1);

        assertEq(1 ether, address(vault).balance);
    }

    function test_execute() public {
        vm.prank(operator);
        bytes memory result = dammModule.execute(
            vault, address(mockRouter), 0, abi.encodeWithSelector(mockRouter.fun1.selector)
        );
        (address caller, uint256 res, uint256 value) =
            abi.decode(result, (address, uint256, uint256));

        assertEq(1, res);
        assertEq(0, value);
        assertEq(vault, caller);

        assertEq(1 ether, address(vault).balance);
    }

    function test_execute_with_value() public {
        vm.prank(operator);
        bytes memory result = dammModule.execute(
            vault, address(mockRouter), 10, abi.encodeWithSelector(mockRouter.fun1.selector)
        );
        (address caller, uint256 res, uint256 value) =
            abi.decode(result, (address, uint256, uint256));
        assertEq(10, value);
        assertEq(1, res);
        assertEq(vault, caller);

        assertEq(1 ether - 10, address(vault).balance);
        assertEq(10, address(mockRouter).balance);
    }

    function testFails_execute_with_revert() public {
        vm.prank(operator);
        bytes memory result = dammModule.execute(
            vault, address(mockRouter), 0, abi.encodeWithSelector(mockRouter.shouldRevert1.selector)
        );
        bytes memory error = abi.decode(result, (bytes));

        assertEq("should revert 1", string(error));
        assertEq(1 ether, address(vault).balance);
    }

    function test_cannot_execute_unauhtorized_router(address badRouter) public {
        vm.assume(badRouter != address(mockRouter));
        vm.assume(badRouter != address(multicallerWithSender));
        vm.assume(badRouter != address(0));

        vm.prank(operator);
        vm.expectRevert(IVaultRouterModule.InvalidRouter.selector);
        dammModule.execute(vault, badRouter, 0, abi.encodeWithSelector(mockRouter.fun1.selector));

        assertEq(1 ether, address(vault).balance);
    }

    function test_execute_multicall() public {
        address[] memory targets = new address[](2);
        targets[0] = address(mockRouter);
        targets[1] = address(mockRouter);

        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encodeWithSelector(mockRouter.fun1.selector);
        datas[1] = abi.encodeWithSelector(mockRouter.fun2.selector);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        vm.prank(operator);
        bytes[] memory results = dammModule.executeMulticall(vault, targets, datas, values);

        (address caller1, uint256 res1, uint256 value1) =
            abi.decode(results[0], (address, uint256, uint256));
        (address caller2, uint256 res2, uint256 value2) =
            abi.decode(results[1], (address, uint256, uint256));

        assertEq(1, res1);
        assertEq(2, res2);
        assertEq(0, value1);
        assertEq(0, value2);
        assertEq(vault, caller1);
        assertEq(vault, caller2);

        assertEq(1 ether, address(vault).balance);
    }

    function test_execute_multicall_with_value() public {
        address[] memory targets = new address[](2);
        targets[0] = address(mockRouter);
        targets[1] = address(mockRouter);

        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encodeWithSelector(mockRouter.fun1.selector);
        datas[1] = abi.encodeWithSelector(mockRouter.fun2.selector);

        uint256[] memory values = new uint256[](2);
        values[0] = 10;
        values[1] = 20;

        vm.prank(operator);
        bytes[] memory results = dammModule.executeMulticall(vault, targets, datas, values);

        (address caller1, uint256 res1, uint256 value1) =
            abi.decode(results[0], (address, uint256, uint256));
        (address caller2, uint256 res2, uint256 value2) =
            abi.decode(results[1], (address, uint256, uint256));

        assertEq(1, res1);
        assertEq(2, res2);
        assertEq(10, value1);
        assertEq(20, value2);
        assertEq(vault, caller1);
        assertEq(vault, caller2);

        assertEq(1 ether - 30, address(vault).balance);
        assertEq(30, address(mockRouter).balance);
    }

    function testFails_execute_multicall_with_revert() public {
        address[] memory targets = new address[](2);
        targets[0] = address(mockRouter);
        targets[1] = address(mockRouter);

        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encodeWithSelector(mockRouter.fun1.selector);
        datas[1] = abi.encodeWithSelector(mockRouter.shouldRevert1.selector);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        vm.prank(operator);
        bytes[] memory results = dammModule.executeMulticall(vault, targets, datas, values);

        (address caller1, uint256 res1, uint256 value1) =
            abi.decode(results[0], (address, uint256, uint256));
        bytes memory error = abi.decode(results[1], (bytes));

        assertEq("should revert 1", string(error));
        assertEq(1, res1);
        assertEq(0, value1);
        assertEq(vault, caller1);

        assertEq(1 ether, address(vault).balance);
    }

    function test_enable_operator(address op) public {
        vm.assume(op != address(0));

        vm.prank(vault);
        dammModule.setOperator(op, true);
        assertTrue(dammModule.operators(keccak256(abi.encode(vault, op))));

        vm.prank(vault);
        dammModule.setOperator(op, false);
        assertFalse(dammModule.operators(keccak256(abi.encode(vault, op))));
    }

    function test_only_vault_can_enable_operator(address notVault) public {
        vm.assume(notVault != vault);

        vm.expectRevert(IVaultRouterModule.NotDAMMVault.selector);
        vm.prank(notVault);
        dammModule.setOperator(operator, true);
    }

    function test_cannot_set_zero_address_as_operator() public {
        vm.expectRevert("VaultRouterModule: operator is zero address");
        vm.prank(vault);
        dammModule.setOperator(address(0), true);
    }

    function test_suspend_trading() public {
        vm.prank(vault);
        dammModule.suspendTrading();
        assertTrue(dammModule.tradingSuspended(vault));

        vm.prank(vault);
        dammModule.resumeTrading();
        assertFalse(dammModule.tradingSuspended(vault));
    }

    function test_only_vault_can_suspend_trading(address notVault) public {
        vm.assume(notVault != vault);

        vm.expectRevert(IVaultRouterModule.NotDAMMVault.selector);
        vm.prank(notVault);
        dammModule.suspendTrading();
    }
}
