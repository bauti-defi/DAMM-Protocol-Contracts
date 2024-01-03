// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPausableActions} from "@src/interfaces/libs/IPausableActions.sol";
import {IOwnableActions} from "@src/interfaces/libs/IOwnableActions.sol";

interface IProtocolStateActions is IPausableActions, IOwnableActions {}
