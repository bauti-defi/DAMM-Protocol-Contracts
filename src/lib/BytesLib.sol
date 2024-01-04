// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

library BytesLib {
    /// @dev assumes addresses packed by: abi.encodePacked(...)
    function unpackAddresses(bytes memory packed) internal pure returns (address[] memory array) {
        return unpack(packed, true, 20);
    }

    /// @dev keep private until needed for other types
    /// @notice heavily inspired from: https://github.com/latticexyz/mud/blob/cb731e0937e614bb316e6bc824813799559956c8/packages/store/src/tightcoder/TightCoder.sol#L68C5-L68C5
    function unpack(bytes memory packed, bool leftAligned, uint256 elementSize)
        private
        pure
        returns (address[] memory array)
    {
        uint256 packedLength = packed.length;

        uint256 padLeft = leftAligned ? 0 : 256 - elementSize * 8;
        // Array length (number of elements)
        uint256 arrayLength;
        unchecked {
            arrayLength = packedLength / elementSize;
        }

        if (packedLength % elementSize != 0) {
            revert("unpackToArray: packedLength must be a multiple of elementSize");
        }

        /// @solidity memory-safe-assembly
        assembly {
            // Allocate a word for each element, and a word for the array's length
            let allocateBytes := add(mul(arrayLength, 32), 0x20)
            // Allocate memory and update the free memory pointer
            array := mload(0x40)
            mstore(0x40, add(array, allocateBytes))

            // Store array length
            mstore(array, arrayLength)

            for {
                let i := 0
                let arrayCursor := add(array, 0x20) // skip array length
                let packedCursor := add(packed, 0x14) // skip packed length
            } lt(i, arrayLength) {
                // Loop until we reach the end of the array
                i := add(i, 1)
                arrayCursor := add(arrayCursor, 0x20) // increment array pointer by one word
                packedCursor := add(packedCursor, elementSize) // increment packed pointer by one element size
            } { mstore(arrayCursor, shr(padLeft, mload(packedCursor))) } // unpack one array element
        }
    }
}
