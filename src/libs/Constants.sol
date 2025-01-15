// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

/// @dev follows EIP-5211 https://eips.ethereum.org/EIPS/eip-5211
address constant NATIVE_ASSET = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

uint256 constant BP_DIVISOR = 10_000;

// FundCallbackHandler
uint256 constant NULL_ROLE = 1 << 0;
uint256 constant FUND_ROLE = 1 << 1;
uint256 constant POSITION_OPENER_ROLE = 1 << 2;
uint256 constant POSITION_CLOSER_ROLE = 1 << 3;
uint256 constant PAUSER_ROLE = 1 << 4;

// safe operations
uint8 constant CALL = 0;
uint8 constant DELEGATE_CALL = 1;
