// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseHook} from "@src/hooks/BaseHook.sol";
import {ICurvePool} from "@src/interfaces/external/ICurvePool.sol";
import {IBeforeTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {Errors} from "@src/libs/Errors.sol";
import "@src/libs/Constants.sol";

event CurveCallValidator_PairEnabled(int128 i, int128 j, int256 key);

event CurveCallValidator_PairDisabled(int128 i, int128 j, int256 key);

error CurveCallValidator_PairNotWhitelisted();

contract CurveCallValidator is BaseHook, IBeforeTransaction {
    ICurvePool public immutable curvePool;

    mapping(int256 packedPair => bool isWhitelisted) public whitelistedPairs;

    constructor(address _fund, address _curvePool) BaseHook(_fund) {
        curvePool = ICurvePool(_curvePool);
    }

    function checkBeforeTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256,
        bytes calldata data
    ) external view override onlyFund expectOperation(operation, CALL) {
        if (target != address(curvePool)) {
            revert Errors.Hook_InvalidTargetAddress();
        }

        if (selector != curvePool.exchange.selector) {
            revert Errors.Hook_InvalidTargetSelector();
        }

        int128 i;
        int128 j;

        assembly {
            i := calldataload(data.offset)
            j := calldataload(add(data.offset, 0x20))
        }

        if (!whitelistedPairs[packInt128s(i, j)]) {
            revert CurveCallValidator_PairNotWhitelisted();
        }
    }

    /**
     * @notice Packs two int128 values into a single int256
     * @param i The higher 128 bits (most significant int128)
     * @param j The lower 128 bits (least significant int128)
     * @return packed The packed int256 value
     */
    function packInt128s(int128 i, int128 j) private pure returns (int256 packed) {
        // Cast the higher 128 bits to int256 and shift it left by 128 bits
        int256 high = int256(i) << 128;

        // Cast the lower 128 bits to int256 using masking
        int256 low = int256(uint256(uint128(j)));

        // Combine the two parts using bitwise OR
        packed = high | low;
    }

    /**
     * @notice Unpacks a single int256 into two int128 values
     * @param packed The packed int256 value
     * @return i The higher 128 bits (most significant int128)
     * @return j The lower 128 bits (least significant int128)
     */
    function unpackInt128s(int256 packed) private pure returns (int128 i, int128 j) {
        // Extract the higher 128 bits by right-shifting 128 bits
        i = int128(packed >> 128);

        // Extract the lower 128 bits by masking with uint256 and then casting
        uint128 lowerBits = uint128(uint256(packed) & type(uint128).max);
        j = int128(lowerBits);
    }

    function enablePair(int128 i, int128 j) external onlyFund {
        int256 packed = packInt128s(i, j);
        whitelistedPairs[packed] = true;

        emit CurveCallValidator_PairEnabled(i, j, packed);
    }

    function disablePair(int128 i, int128 j) external onlyFund {
        int256 packed = packInt128s(i, j);
        whitelistedPairs[packed] = false;

        emit CurveCallValidator_PairDisabled(i, j, packed);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IBeforeTransaction).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
