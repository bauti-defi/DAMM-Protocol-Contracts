// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@src/interfaces/IOracle.sol";
import "@src/interfaces/external/AggregatorV2V3Interface.sol";

import "@src/oracles/OracleStructs.sol";

import {InvalidRound, StaleFeed, GracePeriod, InvalidPrice} from "@src/oracles/OracleErrors.sol";

contract ChainlinkL1PriceOracle is IOracle {
    uint256 public immutable priceFeedGracePeriod;
    address public immutable override asset;
    AggregatorV2V3Interface public immutable chainlinkPriceFeed;

    ValuationHistory private valuations;

    constructor(address asset_, address chainlinkPriceFeed_, uint256 priceFeedGracePeriod_) {
        asset = asset_;
        chainlinkPriceFeed = AggregatorV2V3Interface(chainlinkPriceFeed_);
        priceFeedGracePeriod = priceFeedGracePeriod_;
    }

    function getValuation() external override returns (uint256 valuation, uint256 timestamp) {
        (uint80 priceRoundId, int256 price, uint256 priceStartedAt, uint256 priceUpdatedAt,) =
            chainlinkPriceFeed.latestRoundData();

        uint256 latestRound = chainlinkPriceFeed.latestRound();

        if (priceRoundId < latestRound) revert InvalidRound();
        if (block.timestamp - priceStartedAt < priceFeedGracePeriod) revert GracePeriod();
        if (price < 0) revert InvalidPrice();

        valuation = uint256(price);
        timestamp = priceUpdatedAt;

        _insertValuation(valuation, timestamp);
    }

    function _insertValuation(uint256 value, uint256 timestamp) private {
        valuations.add(value, timestamp);

        emit ValuationUpdated(valuations.count() - 1, timestamp, value);
    }

    function getLatestValuation() public view returns (uint256 valuation, uint256 timestamp) {
        return valuations.getLatest();
    }

    function getValuation(uint256 index)
        public
        view
        returns (uint256 valuation, uint256 timestamp)
    {
        return valuations.get(index);
    }

    function getValuationCount() public view returns (uint256) {
        return valuations.count();
    }

    function decimals() external view override returns (uint8) {
        return chainlinkPriceFeed.decimals();
    }
}
