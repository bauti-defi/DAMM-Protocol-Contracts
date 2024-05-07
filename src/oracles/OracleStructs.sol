// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ValuationHistoryEmpty} from "@src/oracles/OracleErrors.sol";

struct Valuation {
    uint256 timestamp;
    uint256 value;
}

struct ValuationHistory {
    Valuation[] timeseries;
}

function getLatest(ValuationHistory storage history)
    view
    returns (uint256 valuation, uint256 timestamp)
{
    if (history.timeseries.length == 0) {
        revert ValuationHistoryEmpty();
    }

    Valuation memory val = history.timeseries[history.timeseries.length - 1];

    valuation = val.value;
    timestamp = val.timestamp;
}

function get(ValuationHistory storage history, uint256 index)
    view
    returns (uint256 valuation, uint256 timestamp)
{
    if (history.timeseries.length == 0) {
        revert ValuationHistoryEmpty();
    }

    Valuation memory val = history.timeseries[index];

    valuation = val.value;
    timestamp = val.timestamp;
}

function count(ValuationHistory storage history) view returns (uint256) {
    return history.timeseries.length;
}

function add(ValuationHistory storage history, uint256 timestamp, uint256 value) {
    history.timeseries.push(Valuation(timestamp, value));
}

using {getLatest, get, count, add} for ValuationHistory global;
