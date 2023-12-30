// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library AddressConverter {
    function toUint256(address addr) internal pure returns (uint256) {
        return uint256(uint160(addr));
    }
}
