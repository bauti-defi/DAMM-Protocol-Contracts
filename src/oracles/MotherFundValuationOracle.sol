// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IMotherFund} from "@src/interfaces/IMotherFund.sol";
import {FundValuationOracle} from "@src/oracles/FundValuationOracle.sol";

contract MotherFundValuationOracle is FundValuationOracle {
    constructor(address _oracleRouter) FundValuationOracle(_oracleRouter) {}

    /// @notice the amount is ignored for valuation of fund
    /// @notice the base address is the mother fund
    function _getQuote(uint256, address base, address quote)
        internal
        view
        override
        returns (uint256 total)
    {
        total = super._getQuote(0, base, quote);

        address[] memory childFunds = IMotherFund(base).getChildFunds();
        uint256 childFundsLength = childFunds.length;

        for (uint256 i = 0; i < childFundsLength;) {
            total += oracleRouter.getQuote(0, childFunds[i], quote);

            unchecked {
                ++i;
            }
        }
    }
}
