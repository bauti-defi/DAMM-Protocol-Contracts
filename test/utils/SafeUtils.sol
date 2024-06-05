// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@forge-std/Vm.sol";
import {Safe} from "@safe-contracts/Safe.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";

struct SafeTransaction {
    uint256 value;
    address target;
    Enum.Operation operation;
    bytes transaction;
}

library SafeUtils {
    address private constant VM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    Vm private constant vm = Vm(VM_ADDRESS);

    function buildSafeSignatures(bytes memory privateKeys, bytes32 transactionHash, uint256 numKeys)
        internal
        pure
        returns (bytes memory safeSignatures)
    {
        uint256 i;
        for (i = 0; i < numKeys; i++) {
            uint256 privateKey;
            assembly {
                let keyPosition := mul(0x20, i)
                privateKey := mload(add(privateKeys, add(keyPosition, 0x20)))
            }

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, transactionHash);
            safeSignatures = abi.encodePacked(safeSignatures, abi.encodePacked(r, s, v));
        }
    }

    function getTrxSignature(Safe safe, uint256 signerPK, SafeTransaction memory safeTransaction)
        internal
        view
        returns (bytes memory trxSignature)
    {
        bytes memory transactionData = safe.encodeTransactionData(
            safeTransaction.target,
            safeTransaction.value,
            safeTransaction.transaction,
            safeTransaction.operation,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            safe.nonce()
        );

        return SafeUtils.buildSafeSignatures(abi.encode(signerPK), keccak256(transactionData), 1);
    }

    function executeTrx(Safe safe, uint256 signerPK, SafeTransaction memory safeTransaction)
        internal
        returns (bool success)
    {
        vm.startPrank(vm.rememberKey(signerPK), vm.rememberKey(signerPK));
        success = safe.execTransaction(
            safeTransaction.target,
            safeTransaction.value,
            safeTransaction.transaction,
            safeTransaction.operation,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            getTrxSignature(safe, signerPK, safeTransaction)
        );
        vm.stopPrank();
    }
}
