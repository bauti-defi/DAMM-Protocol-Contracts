// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ValuationHistoryEmpty} from "@src/oracles/OracleErrors.sol";

struct Valuation {
    uint256 value;
    uint256 timestamp;
}

struct ValuationHistory {
    Valuation[] timeseries;
}

function getLatest(ValuationHistory storage history)
    view
    returns (uint256 valuation, uint256 timestamp)
{
    if (history.isEmpty()) {
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
    if (history.isEmpty()) {
        revert ValuationHistoryEmpty();
    }

    Valuation memory val = history.timeseries[index];

    valuation = val.value;
    timestamp = val.timestamp;
}

function count(ValuationHistory storage history) view returns (uint256) {
    return history.timeseries.length;
}

function add(ValuationHistory storage history, uint256 value, uint256 timestamp) {
    history.timeseries.push(Valuation(value, timestamp));
}

function isEmpty(ValuationHistory storage history) view returns (bool) {
    return history.timeseries.length == 0;
}

using {getLatest, get, count, add, isEmpty} for ValuationHistory global;
