// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISafe} from "@src/interfaces/ISafe.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";

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
}
