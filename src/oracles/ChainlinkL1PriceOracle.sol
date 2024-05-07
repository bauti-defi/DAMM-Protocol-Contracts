// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@src/interfaces/IOracle.sol";
import "@src/interfaces/external/AggregatorV2V3Interface.sol";

import {InvalidRound, StaleFeed, GracePeriod, InvalidPrice} from "@src/oracles/OracleErrors.sol";

contract ChainlinkL1PriceOracle is IOracle {
    event ValuationUpdated(uint256 index, uint256 timestamp, uint256 value);

    uint256 public immutable priceFeedGracePeriod;
    address public immutable override asset;
    AggregatorV2V3Interface public immutable chainlinkPriceFeed;

    constructor(address asset_, address chainlinkPriceFeed_, uint256 priceFeedGracePeriod_) {
        asset = asset_;
        chainlinkPriceFeed = AggregatorV2V3Interface(chainlinkPriceFeed_);
        priceFeedGracePeriod = priceFeedGracePeriod_;
    }

    function getValuationInUSD() external override returns (uint256 valuation, uint256 timestamp) {
        (uint80 priceRoundId, int256 price, uint256 priceStartedAt, uint256 priceUpdatedAt,) =
            chainlinkPriceFeed.latestRoundData();

        uint256 latestRound = chainlinkPriceFeed.latestRound();

        if (priceRoundId < latestRound) revert InvalidRound();
        if (block.timestamp - priceStartedAt < priceFeedGracePeriod) revert GracePeriod();
        if (price < 0) revert InvalidPrice();

        valuation = uint256(price);
        timestamp = priceUpdatedAt;
    }

    function decimals() external view override returns (uint8) {
        return chainlinkPriceFeed.decimals();
    }
}
