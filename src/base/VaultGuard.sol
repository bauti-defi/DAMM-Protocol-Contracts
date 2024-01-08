// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseGuard} from "@safe-contracts/base/GuardManager.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {IProtocolAddressRegistry} from "@src/interfaces/IProtocolAddressRegistry.sol";
import {IVaultGuard} from "@src/interfaces/IVaultGuard.sol";

contract VaultGuard is BaseGuard, IVaultGuard {
    error TransactionNotAllowed();

    // bytes4(keccak256("setGuard(address)"));
    bytes4 constant GNOSIS_SAFE_SET_GUARD_SELECTOR = 0xe19a9dd9;

    // bytes4(keccak256("enableModule(address)"));
    bytes4 constant GNOSIS_SAFE_ENABLE_MODULE_SELECTOR = 0x610b5925;

    // bytes4(keccak256("disableModule(address,address)"));
    bytes4 constant GNOSIS_SAFE_DISABLE_MODULE_SELECTOR = 0xe009cfde;

    /// TODO: calc this before launch
    // bytes4 public constant GUARD_INTERFACE_ID = 0xe6d7a83a;

    IProtocolAddressRegistry private immutable ADDRESS_REGISTRY;

    constructor(IProtocolAddressRegistry addressRegistry) {
        ADDRESS_REGISTRY = addressRegistry;
    }

    function checkTransaction(
        address,
        uint256,
        bytes memory data,
        Enum.Operation operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address
    ) external pure override {
        require(operation == Enum.Operation.Call, "VaultGuard: delegatecall not allowed");

        bytes4 selector;

        assembly {
            selector := mload(add(data, 32))
        }

        if (
            selector == GNOSIS_SAFE_DISABLE_MODULE_SELECTOR
                || selector == GNOSIS_SAFE_ENABLE_MODULE_SELECTOR
                || selector == GNOSIS_SAFE_SET_GUARD_SELECTOR
        ) {
            revert TransactionNotAllowed();
        }
    }

    function checkAfterExecution(bytes32 txHash, bool success) external override {}
}
