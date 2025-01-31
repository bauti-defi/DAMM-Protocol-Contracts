// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {BaseAdapter} from "@euler-price-oracle/adapter/BaseAdapter.sol";
import {IPriceOracle} from "@euler-price-oracle/interfaces/IPriceOracle.sol";
import {IERC20} from "@openzeppelin-contracts/interfaces/IERC20.sol";
import {NATIVE_ASSET} from "@src/libs/constants.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";

struct Balance {
    address asset;
    address holder;
}

error IndexOutOfBounds();

/// @title Balance Of Oracle
/// @notice Oracle for aggregating the balance of a list of assets
contract BalanceOfOracle is BaseAdapter, Ownable {
    string public constant override name = "BalanceOfOracle";

    /// @notice The Euler Oracle Router used for price lookups
    /// @dev Should be a Euler Oracle Router
    IPriceOracle public immutable oracleRouter;

    Balance[] private balancesToValuate;

    /// @notice Creates a new balance of oracle
    /// @param _owner The address of the owner
    /// @param _oracleRouter Address of the Euler Oracle Router
    constructor(address _owner, address _oracleRouter) Ownable(_owner) {
        oracleRouter = IPriceOracle(_oracleRouter);
    }

    /// @notice Calculates the total value of a list of assets in terms of the quote asset
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
        Balance[] memory balances = balancesToValuate;
        uint256 balanceLength = balances.length;

        if (balanceLength == 0) return 0;

        for (uint256 i = 0; i < balanceLength;) {
            uint256 balance;

            /// native asset
            if (balances[i].asset == NATIVE_ASSET) {
                balance = balances[i].holder.balance;
            } else {
                balance = IERC20(balances[i].asset).balanceOf(balances[i].holder);
            }

            /// calculate how much quote for this amount of asset
            total += balance > 0 ? oracleRouter.getQuote(balance, balances[i].asset, quote) : 0;

            unchecked {
                ++i;
            }
        }
    }

    function addBalanceToValuate(address _asset, address _holder) external onlyOwner {
        balancesToValuate.push(Balance(_asset, _holder));
    }

    function removeBalanceToValuate(uint256 _index) external onlyOwner {
        if (_index >= balancesToValuate.length) revert IndexOutOfBounds();
        balancesToValuate[_index] = balancesToValuate[balancesToValuate.length - 1];
        balancesToValuate.pop();
    }

    function getBalancesToValuate() external view returns (Balance[] memory) {
        return balancesToValuate;
    }
}
