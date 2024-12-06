// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseHook} from "@src/hooks/BaseHook.sol";
import {ICurvePool} from "@src/interfaces/external/ICurvePool.sol";
import {IBeforeTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {Errors} from "@src/libs/Errors.sol";
import "@src/libs/Constants.sol";

error CurveCallValidator_InvalidAssetPool();

event CurveCallValidator_AssetPoolEnabled(address pool, int128 i, int128 j);

event CurveCallValidator_AssetPoolDisabled(address pool, int128 i, int128 j);

contract CurveCallValidator is BaseHook, IBeforeTransaction {
    mapping(bytes32 pointer => bool isWhitelisted) public assetPoolWhitelist;

    constructor(address _fund) BaseHook(_fund) {}

    function checkBeforeTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256,
        bytes calldata data
    ) external view override onlyFund expectOperation(operation, CALL) {
        if (selector != ICurvePool.exchange.selector) {
            revert Errors.Hook_InvalidTargetSelector();
        }

        int128 i;
        int128 j;

        assembly {
            i := calldataload(data.offset)
            j := calldataload(add(data.offset, 0x20))
        }

        if (!assetPoolWhitelist[_createPointer(target, i, j)]) {
            revert CurveCallValidator_InvalidAssetPool();
        }
    }

    function _createPointer(address pool, int128 i, int128 j) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(pool, i, j));
    }

    function enableAssetPool(address pool, int128 i, int128 j) external onlyFund {
        assetPoolWhitelist[_createPointer(pool, i, j)] = true;

        emit CurveCallValidator_AssetPoolEnabled(pool, i, j);
    }

    function disableAssetPool(address pool, int128 i, int128 j) external onlyFund {
        assetPoolWhitelist[_createPointer(pool, i, j)] = false;

        emit CurveCallValidator_AssetPoolDisabled(pool, i, j);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IBeforeTransaction).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
