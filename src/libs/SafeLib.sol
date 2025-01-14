// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISafe} from "@src/interfaces/ISafe.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {Errors} from "@src/libs/Errors.sol";

library SafeLib {
    function executeAndReturnDataOrRevert(
        ISafe safe,
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

    function transferAssetFromSafeOrRevert(ISafe safe, address asset_, address to_, uint256 amount_)
        internal
    {
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
