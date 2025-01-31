// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

/// @dev follows EIP-5211 https://eips.ethereum.org/EIPS/eip-5211
address constant NATIVE_ASSET = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

uint256 constant BP_DIVISOR = 10_000;

// safe operations
uint8 constant CALL = 0;
uint8 constant DELEGATE_CALL = 1;
