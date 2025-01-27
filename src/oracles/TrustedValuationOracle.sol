// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {BaseAdapter, Errors} from "@euler-price-oracle/adapter/BaseAdapter.sol";
import {IPriceOracle} from "@euler-price-oracle/interfaces/IPriceOracle.sol";
import {ScaleUtils, Scale} from "@euler-price-oracle/lib/ScaleUtils.sol";

/// @notice Event emitted when the rate is updated.
/// @param rate The new rate.
/// @param validUntil The timestamp until the rate is valid.
event RateUpdated(uint256 rate, uint256 validUntil);

/// @title TrustedValuationOracle
contract TrustedValuationOracle is BaseAdapter {    
    /// @inheritdoc IPriceOracle
    string public constant name = "FixedRateOracle";
    /// @notice The address of the base asset.
    address public immutable base;
    /// @notice The address of the quote asset.
    address public immutable quote;
    /// @notice The scale factors used for decimal conversions.
    Scale internal immutable scale;
    /// @notice The admin address.
    address public immutable admin;
    /// @notice The fixed conversion rate between base and quote.
    /// @dev Must be given in the quote asset's decimals.
    uint256 public rate;
    /// @notice The timestamp of the last rate update.
    uint256 public lastUpdate;
    /// @notice The timestamp of the last price validation.
    uint256 public priceValidUntil;

    /// @notice Deploy a FixedRateOracle.
    /// @param _admin The address of the admin.
    /// @param _base The address of the base asset.
    /// @param _quote The address of the quote asset.
    /// @param _rate The fixed conversion rate between base and quote.
    /// @dev `_rate` must be given in the quote asset's decimals.
    constructor(address _admin, address _base, address _quote, uint256 _rate) {
        if (_rate == 0) revert Errors.PriceOracle_InvalidConfiguration();
        admin = _admin;
        base = _base;
        quote = _quote;
        rate = _rate;
        lastUpdate = block.timestamp;
        /// @dev set the price valid until to the last update timestamp - 1 to avoid immediate validation
        priceValidUntil = lastUpdate - 1;
        uint8 baseDecimals = _getDecimals(base);
        uint8 quoteDecimals = _getDecimals(quote);
        scale = ScaleUtils.calcScale(baseDecimals, quoteDecimals, quoteDecimals);

        emit RateUpdated(_rate, priceValidUntil);
    }

    /// @notice Update the rate.
    /// @param _rate The new rate.
    /// @param _validUntil The timestamp until the rate is valid.
    function updateRate(uint256 _rate, uint256 _validUntil) external {
        require(msg.sender == admin, "Only admin can call this function");
        if (_rate == 0) revert Errors.PriceOracle_InvalidConfiguration();
        rate = _rate;
        lastUpdate = block.timestamp;
        priceValidUntil = _validUntil;

        emit RateUpdated(_rate, _validUntil);
    }

    /// @notice Get a quote by applying the fixed exchange rate.
    /// @param inAmount The amount of `base` to convert.
    /// @param _base The token that is being priced.
    /// @param _quote The token that is the unit of account.
    /// @return The converted amount using the fixed exchange rate.
    function _getQuote(uint256 inAmount, address _base, address _quote) internal view override returns (uint256) {
        if (block.timestamp > priceValidUntil) revert Errors.PriceOracle_TooStale(block.timestamp - priceValidUntil, priceValidUntil - lastUpdate);
        bool inverse = ScaleUtils.getDirectionOrRevert(_base, base, _quote, quote);
        return ScaleUtils.calcOutAmount(inAmount, rate, scale, inverse);
    }
}
