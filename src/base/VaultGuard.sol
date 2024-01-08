// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseGuard} from "@safe-contracts/base/GuardManager.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import "@openzeppelin-contracts/interfaces/IERC165.sol";
import {IProtocolAddressRegistry} from "@src/interfaces/IProtocolAddressRegistry.sol";
import {IVaultGuard} from "@src/interfaces/IVaultGuard.sol";

contract VaultGuard is BaseGuard, IVaultGuard {
    error NoFunctionSelectorFound(bytes data);

    /// TODO: calc this before launch
    // bytes4 public constant GUARD_INTERFACE_ID = 0xe6d7a83a;

    IProtocolAddressRegistry private immutable ADDRESS_REGISTRY;

    constructor(IProtocolAddressRegistry addressRegistry) {
        ADDRESS_REGISTRY = addressRegistry;
    }

    function checkTransaction(
        address to,
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
    ) external view override {
        require(operation == Enum.Operation.Call, "VaultGuard: delegatecall not allowed");

        // block @here
        // enable/disable module
        // enable/disable guard

        // actions allowed by vault
        // enable/disable operator
        // enable/disable router
        // enable/disable token
        // transfer erc20
        // transfer erc721
        // transfer erc1155
        // transfer eth
        // call withdrawl
        // call router(s)
    }

    function checkAfterExecution(bytes32 txHash, bool success) external override {}

    function _getFunctionSelector(bytes memory data) internal pure returns (bytes4 selector) {
        if (data.length < 4) {
            revert NoFunctionSelectorFound(data);
        }

        assembly {
            selector := mload(add(data, 32))
        }
    }
}
