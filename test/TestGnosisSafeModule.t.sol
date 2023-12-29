// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";
import {BaseVault} from "@test/base/BaseVault.sol";

contract MockRouter {
    function fun1() external payable returns (address, uint256, uint256) {
        return (msg.sender, 1, msg.value);
    }

    function fun2() external payable returns (address, uint256, uint256) {
        return (msg.sender, 2, msg.value);
    }

    function shouldRevert1() external pure {
        revert("should revert 1");
    }
}

contract TestGnosisSafeModule is BaseVault {
    address public operator;
    MockRouter public mockRouter;

    function setUp() public override {
        super.setUp();

        operator = makeAddr("Operator");

        dammModule.setOperator(operator, true);

        mockRouter = new MockRouter();
        vm.label(address(mockRouter), "MockRouter");

        dammModule.setRouter(address(mockRouter), true);

        vm.deal(vault, 1 ether);
    }

    function test_execute() public {
        vm.prank(operator);
        bytes memory result =
            dammModule.execute(vault, address(mockRouter), 0, abi.encodeWithSelector(mockRouter.fun1.selector));
        (address caller, uint256 res, uint256 value) = abi.decode(result, (address, uint256, uint256));

        assertEq(1, res);
        assertEq(0, value);
        assertEq(vault, caller);

        assertEq(1 ether, address(vault).balance);
    }

    function test_execute_with_value() public {
        vm.prank(operator);
        bytes memory result =
            dammModule.execute(vault, address(mockRouter), 10, abi.encodeWithSelector(mockRouter.fun1.selector));
        (address caller, uint256 res, uint256 value) = abi.decode(result, (address, uint256, uint256));
        assertEq(10, value);
        assertEq(1, res);
        assertEq(vault, caller);

        assertEq(1 ether - 10, address(vault).balance);
        assertEq(10, address(mockRouter).balance);
    }

    function testFails_execute_with_revert() public {
        vm.prank(operator);
        bytes memory result =
            dammModule.execute(vault, address(mockRouter), 0, abi.encodeWithSelector(mockRouter.shouldRevert1.selector));
        bytes memory error = abi.decode(result, (bytes));

        assertEq("should revert 1", string(error));
        assertEq(1 ether, address(vault).balance);
    }

    function test_cannot_execute_unauhtorized_router(address badRouter) public {
        vm.assume(badRouter != address(mockRouter));
        vm.assume(badRouter != address(multicallerWithSender));
        vm.assume(badRouter != address(0));

        vm.prank(operator);
        vm.expectRevert("GnosisSafeModule: target is not router");
        dammModule.execute(vault, badRouter, 0, abi.encodeWithSelector(mockRouter.fun1.selector));

        assertEq(1 ether, address(vault).balance);
    }
}
