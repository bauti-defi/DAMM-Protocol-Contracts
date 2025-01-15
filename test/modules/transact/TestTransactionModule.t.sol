// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {console2} from "@forge-std/Test.sol";
import {TestBaseFund} from "@test/base/TestBaseFund.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {TransactionModule} from "@src/modules/transact/TransactionModule.sol";
import {ITransactionModule} from "@src/interfaces/ITransactionModule.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {SafeUtils, SafeTransaction} from "@test/utils/SafeUtils.sol";
import {IBeforeTransaction, IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {BaseHook} from "@src/hooks/BaseHook.sol";
import "@src/libs/Errors.sol";
import "@src/modules/transact/Hooks.sol";
import "@src/modules/transact/HookRegistry.sol";
import "@src/modules/transact/Structs.sol";

contract MockTarget {
    uint256 public value;

    event Message(string message);

    function increment(uint256 _value) public {
        value += _value;
    }

    function triggerRevert() public pure {
        revert("MockTarget revert");
    }

    function emitMessage(string memory message) public payable returns (string memory) {
        emit Message(message);

        return message;
    }
}

contract VerifyValueHook is BaseHook, IBeforeTransaction {
    constructor() BaseHook(address(0)) {}

    function checkBeforeTransaction(address, bytes4, uint8, uint256 value, bytes memory)
        external
        pure
        override
    {
        require(value > 0, "Value must be greater than 0");
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IBeforeTransaction).interfaceId
            || super.supportsInterface(interfaceId);
    }
}

contract RevertBeforeHook is BaseHook, IBeforeTransaction {
    constructor() BaseHook(address(0)) {}

    function checkBeforeTransaction(address, bytes4, uint8, uint256, bytes memory)
        external
        pure
        override
    {
        revert("RevertBeforeHook");
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IBeforeTransaction).interfaceId
            || super.supportsInterface(interfaceId);
    }
}

contract VerifyCallbackHook is BaseHook, IAfterTransaction {
    string internal callback;

    constructor(string memory _callback) BaseHook(address(0)) {
        callback = _callback;
    }

    function checkAfterTransaction(
        address,
        bytes4,
        uint8,
        uint256,
        bytes memory,
        bytes memory returnData
    ) external view override {
        require(
            keccak256(abi.encodePacked(abi.decode(returnData, (string))))
                == keccak256(abi.encodePacked(callback)),
            "Callback mismatch"
        );
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAfterTransaction).interfaceId
            || super.supportsInterface(interfaceId);
    }
}

contract RevertAfterHook is BaseHook, IAfterTransaction {
    constructor() BaseHook(address(0)) {}

    function checkAfterTransaction(address, bytes4, uint8, uint256, bytes memory, bytes memory)
        external
        pure
        override
    {
        revert("RevertAfterHook");
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAfterTransaction).interfaceId
            || super.supportsInterface(interfaceId);
    }
}

contract TestTransactionModule is TestBaseFund, TestBaseProtocol {
    using SafeUtils for SafeL2;

    address internal fundAdmin;
    uint256 internal fundAdminPK;
    HookRegistry internal hookRegistry;
    TransactionModule internal transactionModule;
    MockTarget internal target;
    address internal revertBeforeHook;
    address internal revertAfterHook;

    address internal operator;

    function setUp() public override(TestBaseFund, TestBaseProtocol) {
        TestBaseFund.setUp();
        TestBaseProtocol.setUp();

        operator = makeAddr("Operator");

        (fundAdmin, fundAdminPK) = makeAddrAndKey("FundAdmin");
        vm.deal(fundAdmin, 1000 ether);

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;

        fund =
            fundFactory.deployFund(address(safeProxyFactory), address(safeSingleton), admins, 1, 1);
        vm.label(address(fund), "Fund");
        assertTrue(address(fund) != address(0), "Failed to deploy fund");
        assertTrue(fund.isOwner(fundAdmin), "Fund admin not owner");

        vm.deal(address(fund), 1000 ether);

        hookRegistry = HookRegistry(
            deployContract(
                payable(address(fund)),
                fundAdmin,
                fundAdminPK,
                address(createCall),
                bytes32("hookRegistry"),
                0,
                abi.encodePacked(type(HookRegistry).creationCode, abi.encode(address(fund)))
            )
        );

        vm.label(address(hookRegistry), "HookRegistry");

        transactionModule = TransactionModule(
            deployModule(
                payable(address(fund)),
                fundAdmin,
                fundAdminPK,
                bytes32("transactionModule"),
                0,
                abi.encodePacked(
                    type(TransactionModule).creationCode,
                    abi.encode(address(fund), address(hookRegistry))
                )
            )
        );
        vm.label(address(transactionModule), "TransactionModule");

        assertEq(transactionModule.fund(), address(fund), "TransactionModule fund not set");

        target = new MockTarget();
        vm.label(address(target), "MockTarget");

        revertBeforeHook = address(new RevertBeforeHook());
        vm.label(revertBeforeHook, "RevertBeforeHook");

        revertAfterHook = address(new RevertAfterHook());
        vm.label(revertAfterHook, "RevertAfterHook");

        // have to set gasprice > 0 so that gas refund is calculated
        vm.txGasPrice(100);
        vm.fee(99);
    }

    modifier withHook(HookConfig memory config) {
        vm.prank(address(fund));
        hookRegistry.setHooks(config);
        _;
    }

    function mock_hook() private view returns (HookConfig memory) {
        return HookConfig({
            operator: operator,
            target: address(target),
            beforeTrxHook: address(0),
            afterTrxHook: address(0),
            targetSelector: bytes4(keccak256("increment(uint256)")),
            operation: uint8(Enum.Operation.Call)
        });
    }

    function mock_trigger_revert_hook() private view returns (HookConfig memory config) {
        config = mock_hook();
        config.targetSelector = bytes4(keccak256("triggerRevert()"));
    }

    function mock_revert_before_hook() private view returns (HookConfig memory config) {
        config = mock_hook();
        config.beforeTrxHook = revertBeforeHook;
    }

    function mock_revert_after_hook() private view returns (HookConfig memory config) {
        config = mock_hook();
        config.afterTrxHook = revertAfterHook;
    }

    function mock_custom_hook() private returns (HookConfig memory config) {
        config = mock_hook();
        config.targetSelector = bytes4(keccak256("emitMessage(string)"));

        address beforeHook = address(new VerifyValueHook());
        address afterHook = address(new VerifyCallbackHook("hello world"));

        config.beforeTrxHook = beforeHook;
        config.afterTrxHook = afterHook;
    }

    function incrementCall(uint256 _value) private view returns (Transaction memory trx) {
        trx = Transaction({
            operation: uint8(Enum.Operation.Call),
            target: address(target),
            value: 0,
            data: abi.encode(_value),
            targetSelector: MockTarget.increment.selector
        });
    }

    function triggerRevertCall() private view returns (Transaction memory trx) {
        trx = Transaction({
            target: address(target),
            value: 0,
            operation: uint8(Enum.Operation.Call),
            targetSelector: MockTarget.triggerRevert.selector,
            data: bytes("")
        });
    }

    function emitMessageCall(string memory message, uint256 value)
        private
        view
        returns (Transaction memory trx)
    {
        trx = Transaction({
            target: address(target),
            value: value,
            operation: uint8(Enum.Operation.Call),
            targetSelector: MockTarget.emitMessage.selector,
            data: abi.encode(message)
        });
    }

    /// @dev this function is used to generate test data for the SDK
    // function test_generate_sdk_test_data() public withHook(mock_hook()) {
    //     Transaction[] memory calls = new Transaction[](4);
    //     calls[0] = incrementCall(10);
    //     calls[1] = incrementCall(20);
    //     calls[2] = incrementCall(0);
    //     calls[3] = incrementCall(500);

    //     console2.logAddress(address(target));
    //     console2.logBytes4(calls[0].targetSelector);
    //     console2.logBytes(calls[0].data);
    //     console2.logBytes4(TransactionModule.execute.selector);
    //     console2.log(makeAddr("testing"));
    //     console2.logBytes(abi.encode(calls));
    //     console2.logBytes(abi.encodeWithSelector(TransactionModule.execute.selector, calls));
    // }

    function test_execute() public withHook(mock_hook()) {
        Transaction[] memory calls = new Transaction[](4);
        calls[0] = incrementCall(10);
        calls[1] = incrementCall(20);
        calls[2] = incrementCall(0);
        calls[3] = incrementCall(500);

        uint256 adjustedFundBalance = address(fund).balance - 530;

        vm.prank(operator);
        transactionModule.execute(calls);

        assertEq(target.value(), 530, "Target value not incremented");
        assertTrue(adjustedFundBalance > address(fund).balance, "gas was not refunded");
    }

    function test_execute_reverts() public withHook(mock_trigger_revert_hook()) {
        vm.expectRevert("MockTarget revert");

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = triggerRevertCall();

        vm.prank(operator);
        transactionModule.execute(calls);
    }

    function test_execute_with_full_hooks() public withHook(mock_custom_hook()) {
        Transaction[] memory calls = new Transaction[](1);
        calls[0] = emitMessageCall("hello world", 10);

        vm.prank(operator);
        transactionModule.execute(calls);
    }

    function test_only_operator_can_execute(address attacker) public withHook(mock_hook()) {
        vm.assume(attacker != operator);

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = incrementCall(10);

        vm.expectRevert(Errors.Transaction_HookNotDefined.selector);
        vm.prank(attacker);
        transactionModule.execute(calls);
    }

    function test_revert_before_hook() public withHook(mock_revert_before_hook()) {
        Transaction[] memory calls = new Transaction[](1);
        calls[0] = incrementCall(10);

        vm.expectRevert("RevertBeforeHook");
        vm.prank(operator);
        transactionModule.execute(calls);
    }

    function test_revert_after_hook() public withHook(mock_revert_after_hook()) {
        Transaction[] memory calls = new Transaction[](1);
        calls[0] = incrementCall(10);

        vm.expectRevert("RevertAfterHook");
        vm.prank(operator);
        transactionModule.execute(calls);
    }
}
