// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {BaseAdapter, Errors, IPriceOracle} from "@euler-price-oracle/adapter/BaseAdapter.sol";
import {AggregatorV3Interface} from
    "@euler-price-oracle/adapter/chainlink/AggregatorV3Interface.sol";

/// @dev This Oracle is a wrapper for any Chainlink oracle on L2.
/// It uses the L2 sequencer feed to check that the sequencer is running.
contract ChainlinkL2SequencerOracle is BaseAdapter {
    string public constant name = "ChainlinkL2Oracle";

    address public immutable sequencerFeed;
    address public immutable chainlinkOracle;
    uint256 public immutable l2SequencerUptimeGracePeriod;

    constructor(
        address _sequencerFeed,
        uint256 _l2SequencerUptimeGracePeriod,
        address _chainlinkOracle
    ) {
        sequencerFeed = _sequencerFeed;
        l2SequencerUptimeGracePeriod = _l2SequencerUptimeGracePeriod;
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

        if (answer != 0) revert Errors.PriceOracle_InvalidAnswer();
        if (block.timestamp - startedAt < l2SequencerUptimeGracePeriod) {
            revert Errors.PriceOracle_TooStale(
                block.timestamp - startedAt, l2SequencerUptimeGracePeriod
            );
        }

        return IPriceOracle(chainlinkOracle).getQuote(inAmount, _base, _quote);
    }
}
