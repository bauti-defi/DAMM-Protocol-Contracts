// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {BaseAdapter, Errors, IPriceOracle} from "@euler-price-oracle/adapter/BaseAdapter.sol";
import {AggregatorV3Interface} from
    "@euler-price-oracle/adapter/chainlink/AggregatorV3Interface.sol";

/// @dev This Oracle is a wrapper for any Chainlink oracle on L2.
/// It uses the L2 sequencer feed to check that the sequencer is running.
contract ChainlinkL2Oracle is BaseAdapter {
    string public constant name = "ChainlinkL2Oracle";

    address public immutable sequencerFeed;
    address public immutable chainlinkOracle;
    uint256 public immutable gracePeriodDuration;

    constructor(address _sequencerFeed, uint256 _gracePeriodDuration, address _chainlinkOracle) {
        sequencerFeed = _sequencerFeed;
        gracePeriodDuration = _gracePeriodDuration;
        chainlinkOracle = _chainlinkOracle;
    }

    /// @notice Get the quote from the Chainlink feed.
    /// @param inAmount The amount of `base` to convert.
    /// @param _base The token that is being priced.
    /// @param _quote The token that is the unit of account.
    /// @return The converted amount using the Chainlink feed.
    function _getQuote(uint256 inAmount, address _base, address _quote)
        internal
        view
        override
        returns (uint256)
    {
        (, int256 answer, uint256 startedAt,,) =
            AggregatorV3Interface(sequencerFeed).latestRoundData();
        /// @dev if 0 then sequencer is up, else it is down
        if (answer != 0) revert Errors.PriceOracle_InvalidAnswer();

        /// @notice use `startedAt` instead of `updatedAt`.
        /// Make sure the grace period has passed after the
        /// sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= gracePeriodDuration) {
            revert Errors.PriceOracle_TooStale(timeSinceUp, gracePeriodDuration);
        }

        return IPriceOracle(chainlinkOracle).getQuote(inAmount, _base, _quote);
    }
}
