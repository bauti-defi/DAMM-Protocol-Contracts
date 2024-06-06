// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Role} from "./Structs.sol";

event AssetEnabled(address asset);

event AssetDisabled(address asset);

event AccountOpened(address indexed user, Role role);

event AccountRoleChanged(address indexed user, Role role);

event AccountPaused(address indexed user);

event AccountUnpaused(address indexed user);

event FeeRecipientUpdated(address recipient);

event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);
