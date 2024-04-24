// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.25;

import {console2} from "@forge-std/Test.sol";
import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {SafeUtils} from "@test/utils/SafeUtils.sol";

contract TestSafe is TestBaseGnosis {
    address owner;
    uint256 ownerPK;
    SafeL2 safe;

    address refundReceiver;

    bool reached;

    function setUp() public override {
        super.setUp();

        (owner, ownerPK) = makeAddrAndKey("Owner");

        refundReceiver = makeAddr("RefundReceiver");

        address[] memory admins = new address[](1);
        admins[0] = owner;

        safe = deploySafe(admins, 1);
        vm.label(address(safe), "Safe");
    }

    function hitThis() public payable {
        reached = msg.value > 0;
    }

    function test_this() public {
        uint256 dealt = 100000000;
        uint256 sent = 10000;
        vm.deal(address(safe), dealt);

        uint256 initialBalance = address(this).balance;

        assertEq(owner.balance, 0);

        // @param safeTxGas Gas that should be used for the safe transaction.
        // @param baseGas Gas costs for that are independent of the transaction execution(e.g. base transaction fee, signature check, payment of the refund)
        // @param gasPrice Maximum gas price that should be used for this transaction.
        bytes memory transactionData = safe.encodeTransactionData(
            address(this),
            sent,
            abi.encodeWithSelector(this.hitThis.selector),
            Enum.Operation.Call,
            100000,
            0,
            1,
            address(0),
            payable(address(0)),
            safe.nonce()
        );

        vm.startPrank(vm.rememberKey(ownerPK), vm.rememberKey(ownerPK));
        bool success = safe.execTransaction(
            address(this),
            sent,
            abi.encodeWithSelector(this.hitThis.selector),
            Enum.Operation.Call,
            100000,
            0,
            1,
            address(0),
            payable(address(0)),
            SafeUtils.buildSafeSignatures(abi.encode(ownerPK), keccak256(transactionData), 1)
        );
        vm.stopPrank();

        assertTrue(success, "Transaction failed");
        assertTrue(reached, "Function not reached");
        assertEq(address(this).balance, initialBalance + 10000, "Balance of this");
        assertEq(owner.balance, 12354, "Balance of refund receiver");
        assertEq(address(safe).balance, dealt - sent - owner.balance, "Balance of safe");
        assertEq(owner.balance, 12354, "Balance of owner");
    }
}
