// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";
import {Vm} from "@forge-std/Vm.sol";
import {BaseRouter} from "@src/base/BaseRouter.sol";

contract Router is BaseRouter {
    event CurrentCaller(address caller);

    constructor(address _owner, address _tokenWhitelistRegistry) BaseRouter(_owner, _tokenWhitelistRegistry) {}

    function fun1() external payable returns (uint256) {
        return 1;
    }

    function fun2() external payable returns (uint256) {
        return 2;
    }

    function fun3() external returns (uint256) {
        return 3;
    }

    function fun4() external setCaller returns (uint256) {
        emit CurrentCaller(caller);
        return 4;
    }

    function fun5() external setCaller returns (uint256) {
        emit CurrentCaller(caller);
        return 5;
    }

    function shouldRevert1() external pure {
        revert("should revert 1");
    }
}

contract TestBaseRouter is Test {
    Router router;

    function setUp() public {
        router = new Router(address(0), address(0));
    }

    modifier invariants() {
        /// @notice the caller address is a transient variable that should always be 0 before each transaction
        bytes32 callerAddress = vm.load(address(router), bytes32(uint256(0)));
        assertEq(bytes32(0), callerAddress);
        _;
        /// @notice the caller address is a transient variable that should be reset after each transaction
        callerAddress = vm.load(address(router), bytes32(uint256(0)));
        assertEq(bytes32(0), callerAddress);
    }

    function test_multicall_without_value() public invariants {
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSignature("fun1()");
        data[1] = abi.encodeWithSignature("fun2()");
        data[2] = abi.encodeWithSignature("fun3()");

        bytes[] memory results = router.multicall(data);

        assertEq(results.length, 3);
        assertEq(abi.decode(results[0], (uint256)), 1);
        assertEq(abi.decode(results[1], (uint256)), 2);
        assertEq(abi.decode(results[2], (uint256)), 3);
    }

    function test_multicall_with_value() public invariants {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("fun1()");
        data[1] = abi.encodeWithSignature("fun2()");

        vm.deal(address(this), 1 ether);

        bytes[] memory results = router.multicall{value: 1 wei}(data);

        assertEq(results.length, 2);
        assertEq(abi.decode(results[0], (uint256)), 1);
        assertEq(abi.decode(results[1], (uint256)), 2);
        assertEq(address(this).balance, 1 ether - 1 wei);
        assertEq(address(router).balance, 1 wei);
    }

    function testFails_multicall_with_value_to_non_payable_function() public invariants {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("fun3()");

        vm.deal(address(this), 1 ether);

        router.multicall{value: 1 wei}(data);

        assertEq(address(this).balance, 1 ether);
    }

    function test_multicall_returns_revert_message() public invariants {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("shouldRevert1()");

        vm.expectRevert("should revert 1");
        router.multicall(data);
    }

    function test_caller_is_set() public invariants {
        vm.recordLogs();

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("fun4()");
        data[1] = abi.encodeWithSignature("fun5()");

        bytes[] memory results = router.multicall(data);

        assertEq(results.length, 2);
        assertEq(abi.decode(results[0], (uint256)), 4);
        assertEq(abi.decode(results[1], (uint256)), 5);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 2);

        assertEq(entries[0].emitter, address(router));
        assertEq(entries[0].topics.length, 1);
        assertEq(entries[0].topics[0], bytes32(uint256(keccak256("CurrentCaller(address)"))));
        assertEq(entries[0].data.length, 32);
        assertEq(abi.decode(entries[0].data, (address)), address(this));

        assertEq(entries[1].emitter, address(router));
        assertEq(entries[1].topics.length, 1);
        assertEq(entries[1].topics[0], bytes32(uint256(keccak256("CurrentCaller(address)"))));
        assertEq(entries[1].data.length, 32);
        assertEq(abi.decode(entries[1].data, (address)), address(this));
    }

    function test_multicall_reentrance() public invariants {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("multicall(bytes[])");

        vm.expectRevert();
        router.multicall(data);
    }

    function test_multicall_invalid_function() public invariants {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("thisFunctionDoesNotExist()");

        vm.expectRevert("Router: invalid fallback");
        router.multicall(data);
    }
}
