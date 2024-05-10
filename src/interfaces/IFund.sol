// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IPortfolio.sol";
import "./ISafe.sol";

interface IFund is IPortfolio, ISafe {}
