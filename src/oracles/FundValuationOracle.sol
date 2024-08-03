// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseAdapter} from "@euler-price-oracle/adapter/BaseAdapter.sol";
import {IPriceOracle} from "@euler-price-oracle/interfaces/IPriceOracle.sol";
import "@src/interfaces/IFund.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {NATIVE_ASSET} from "@src/libs/constants.sol";
import "@src/libs/Errors.sol";
import {IMotherFund} from "@src/interfaces/IMotherFund.sol";

contract FundValuationOracle is BaseAdapter {
    string public constant override name = "FundValuationOracle";

    /// @dev should be a Euler Oracle Router
    IPriceOracle public immutable oracleRouter;

    constructor(address _oracleRouter) {
        oracleRouter = IPriceOracle(_oracleRouter);
    }

    /// @notice amount is ignored for valuation of fund
    function _getQuote(uint256, address base, address quote)
        internal
        view
        virtual
        override
        returns (uint256 total)
    {
        /// TODO: validate base as the a fund
        IFund fund = IFund(base);

        if (fund.hasOpenPositions()) revert Errors.FundValuationOracle_FundNotFullyDivested();

        address[] memory assets = fund.getAssetsOfInterest();
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
