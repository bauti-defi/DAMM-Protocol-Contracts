// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@euler-price-oracle/adapter/BaseAdapter.sol";
import {ScaleUtils, Scale} from "@euler-price-oracle/lib/ScaleUtils.sol";

contract MockPriceOracle is BaseAdapter {
    /// @inheritdoc IPriceOracle
    string public constant name = "MockPriceOracle";
    /// @notice The address of the base asset
    address public immutable base;
    /// @notice The address of the quote asset.
    address public immutable quote;
    /// @notice The scale factors used for decimal conversions.
    Scale internal immutable scale;
    /// @notice The price of the base asset in the quote asset.
    uint256 public price;

    /// @param _decimals The decimals of the feed, already incorporated into the price.
    constructor(address _base, address _quote, uint256 _price, uint8 _decimals) {
        base = _base;
        quote = _quote;
        price = _price;

        // The scale factor is used to correctly convert decimals.
        uint8 baseDecimals = _getDecimals(base);
        uint8 quoteDecimals = _getDecimals(quote);
        scale = ScaleUtils.calcScale(baseDecimals, quoteDecimals, _decimals);
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    /// @param inAmount The amount of `base` to convert.
    /// @param _base The token that is being priced.
    /// @param _quote The token that is the unit of account.
    function _getQuote(uint256 inAmount, address _base, address _quote)
        internal
        view
        override
        returns (uint256)
    {
        bool inverse = ScaleUtils.getDirectionOrRevert(_base, base, _quote, quote);

        return ScaleUtils.calcOutAmount(inAmount, price, scale, inverse);
    }
}
