// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {IAvatar} from "@zodiac/interfaces/IAvatar.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {Errors} from "@src/libs/Errors.sol";

/// @title SafeLib
/// @notice Implementation of Safe transaction execution utilities
/// @dev Provides helper functions for executing transactions and transferring assets from Safe contracts
library SafeLib {
    /// @notice Executes a transaction through a Safe contract from a module
    /// @dev The transaction is executed by the Safe contract itself, but initiated by a module
    /// @param safe The Safe contract to execute the transaction from
    /// @param target Destination address of the transaction
    /// @param value Native token value to send with the transaction
    /// @param data Data payload of the transaction
    /// @param operation Operation type (Call or DelegateCall)
    /// @return bytes The return data from the transaction
    function executeAndReturnDataOrRevert(
        IAvatar safe,
        address target,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnData) =
            safe.execTransactionFromModuleReturnData(target, value, data, operation);

        if (!success) {
            assembly {
                /// bubble up revert reason if length > 0
                if gt(mload(returnData), 0) { revert(add(returnData, 0x20), mload(returnData)) }
                /// else revert with no reason
                revert(0, 0)
            }
        }

        return returnData;
    }

    /// @notice Transfers an asset from a Safe to a specified address
    /// @param safe The Safe contract to transfer from
    /// @param asset_ The token address to transfer (or native token address)
    /// @param to_ The recipient address
    /// @param amount_ The amount to transfer
    function transferAssetFromSafeOrRevert(
        IAvatar safe,
        address asset_,
        address to_,
        uint256 amount_
    ) internal {
        /// call fund to transfer asset out
        bytes memory returnData = executeAndReturnDataOrRevert(
            safe,
            asset_,
            0,
            abi.encodeWithSignature("transfer(address,uint256)", to_, amount_),
            Enum.Operation.Call
        );

        /// check transfer was successful
        if (returnData.length > 0 && !abi.decode(returnData, (bool))) {
            revert Errors.AssetTransferFailed();
        }
    }
}
