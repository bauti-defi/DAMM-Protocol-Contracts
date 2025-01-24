// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {BaseAdapter} from "@euler-price-oracle/adapter/BaseAdapter.sol";
import {IPriceOracle} from "@euler-price-oracle/interfaces/IPriceOracle.sol";
import "@src/interfaces/IFund.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {NATIVE_ASSET} from "@src/libs/constants.sol";
import "@src/libs/Errors.sol";
import {IMotherFund} from "@src/interfaces/IMotherFund.sol";

/// @title Fund Valuation Oracle
/// @notice Oracle for calculating the total value of a fund's assets
/// @dev Aggregates values from child funds and direct asset holdings
contract FundValuationOracle is BaseAdapter {
    string public constant override name = "FundValuationOracle";

    /// @notice The Euler Oracle Router used for price lookups
    /// @dev Should be a Euler Oracle Router
    IPriceOracle public immutable oracleRouter;

    /// @notice Creates a new fund valuation oracle
    /// @param _oracleRouter Address of the Euler Oracle Router
    constructor(address _oracleRouter) {
        oracleRouter = IPriceOracle(_oracleRouter);
    }

    /// @notice Calculates the total value of a fund in terms of the quote asset
    /// @notice amount is ignored for valuation of fund
    /// @dev Aggregates values from child funds and direct asset holdings
    /// @param amount Ignored for fund valuation
    /// @param base Address of the fund to valuate
    /// @param quote Address of the quote asset
    /// @return total The total value in terms of the quote asset
    function _getQuote(uint256 amount, address base, address quote)
        internal
        view
        virtual
        override
        returns (uint256 total)
    {
        /// TODO: validate base as the a fund
        IFund fund = IFund(base);

        if (fund.hasOpenPositions()) revert Errors.FundValuationOracle_FundNotFullyDivested();

        address[] memory childFunds = IMotherFund(base).getChildFunds();
        uint256 childFundsLength = childFunds.length;

        for (uint256 i = 0; i < childFundsLength;) {
            total += oracleRouter.getQuote(0, childFunds[i], quote);

            unchecked {
                ++i;
            }
        }

        address[] memory assets = fund.getAssetsToValuate();
        uint256 assetLength = assets.length;

        for (uint256 i = 0; i < assetLength;) {
            uint256 balance;

            /// native asset
            if (assets[i] == NATIVE_ASSET) {
                balance = base.balance;
            } else {
                balance = IERC20(assets[i]).balanceOf(base);
            }

            /// calculate how much liquidity for this amount of asset
            total += balance > 0 ? oracleRouter.getQuote(balance, assets[i], quote) : 0;

            unchecked {
                ++i;
            }
        }
    }
}
