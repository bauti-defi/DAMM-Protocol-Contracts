// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPausableState} from "@src/interfaces/libs/IPausableState.sol";
import {IOwnableState} from "@src/interfaces/libs/IOwnableState.sol";

interface IProtocolState is IPausableState, IOwnableState {}
