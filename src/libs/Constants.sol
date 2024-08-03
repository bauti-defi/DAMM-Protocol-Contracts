// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

address constant NATIVE_ASSET = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

uint256 constant BP_DIVISOR = 10_000;

// FundCallbackHandler
uint256 constant NULL_ROLE = 1 << 0;
uint256 constant FUND_ROLE = 1 << 1;
uint256 constant POSITION_OPENER_ROLE = 1 << 2;
uint256 constant POSITION_CLOSER_ROLE = 1 << 3;

// safe operations
uint8 constant CALL = 0;
uint8 constant DELEGATE_CALL = 1;
