// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@src/interfaces/IOracle.sol";
import "@src/interfaces/external/AggregatorV2V3Interface.sol";

contract ChainlinkL1PriceOracle is IOracle {
    error InvalidRound();
    error StaleFeed();
    error GracePeriod();
    error InvalidPrice();

    uint256 public immutable priceFeedGracePeriod;
    address public immutable override asset;
    AggregatorV2V3Interface public immutable chainlinkPriceFeed;

    constructor(address asset_, address chainlinkPriceFeed_, uint256 priceFeedGracePeriod_) {
        asset = asset_;
        chainlinkPriceFeed = AggregatorV2V3Interface(chainlinkPriceFeed_);
        priceFeedGracePeriod = priceFeedGracePeriod_;
    }

    function getValuationInUSD() external view override returns (uint256 valuation) {
        (uint80 priceRoundId, int256 price, uint256 priceStartedAt, uint256 priceUpdatedAt,) =
            chainlinkPriceFeed.latestRoundData();

        uint256 latestRound = chainlinkPriceFeed.latestRound();

        if (priceRoundId < latestRound) revert InvalidRound();
        if (block.timestamp - priceStartedAt < priceFeedGracePeriod) revert GracePeriod();
        if (block.timestamp - priceUpdatedAt > priceFeedGracePeriod) revert StaleFeed();
        if (price < 0) revert InvalidPrice();

        valuation = uint256(price);
    }

    function decimals() external view override returns (uint8) {
        return chainlinkPriceFeed.decimals();
    }
}
