// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPortfolio} from "@src/interfaces/IPortfolio.sol";
import "@src/libs/Errors.sol";

abstract contract BaseHook {
    IPortfolio public immutable fund;

    constructor(address _fund) {
        fund = IPortfolio(_fund);
    }

    modifier onlyFund() {
        if (msg.sender != address(fund)) {
            revert Errors.OnlyFund();
        }
        _;
    }

    modifier expectOperation(uint8 given, uint8 expected) {
        if (given != expected) {
            revert Errors.Hook_InvalidOperation();
        }
        _;
    }
}
