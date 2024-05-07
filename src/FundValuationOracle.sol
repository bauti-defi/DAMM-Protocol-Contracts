// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@src/interfaces/IFund.sol";
import "@src/interfaces/IOracle.sol";
import "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

// import {ValuationHistoryEmpty} from "@src/oracles/OracleErrors.sol";
import "@src/oracles/OracleStructs.sol";

contract FundValuationOracle is IOracle {
    using EnumerableSet for EnumerableSet.AddressSet;

    event ValuationUpdated(uint256 index, uint256 avgTimestamp, uint256 valuation);
    event AssetEnabled(address oracle);
    event AssetDisabled(address oracle);

    IFund public immutable fund;

    EnumerableSet.AddressSet private oracles;
    ValuationHistory private valuations;

    constructor(address fund_) {
        fund = IFund(fund_);
    }

    modifier onlyFund() {
        require(msg.sender == address(fund), "Only fund can call this function");
        _;
    }

    /// @dev returned timestamp is average of all oracles. caller can check `block.timestamp` externally.
    function getValuationInUSD() public returns (uint256 valuation, uint256 timestamp) {
        // check if fund has an open positions
        require(!fund.hasOpenPositions(), "Fund has open positions");

        /// TODO: make sure L2 sequencer is running!

        // get fund balance of each asset that is to be valuated
        // get USD price of each asset from oracle
        uint256 length = oracles.length();
        for (uint256 i = 0; i < length;) {
            IOracle oracle = IOracle(oracles.at(i));

            // get balance of asset in fund
            uint256 balance = IERC20(oracle.asset()).balanceOf(address(fund));

            // get USD price of asset from oracle
            (uint256 price, uint256 _timestamp) = oracle.getValuationInUSD();

            // sum up the USD value of each asset
            valuation += balance * price;

            // we will also sum the timestamps of each oracle
            timestamp += _timestamp;

            unchecked {
                ++i;
            }
        }

        // lets get the average timestamp
        timestamp = timestamp / length;

        _insertValuation(timestamp, valuation);

        // sum up the USD value of each asset
        // and the average timestamp
        return (valuation, timestamp);
    }

    function asset() public view returns (address) {
        return address(fund);
    }

    /// TODO: make sure this is same as USD oracles
    function decimals() public view returns (uint8) {
        return 8;
    }

    function _insertValuation(uint256 timestamp, uint256 value) private {
        valuations.add(timestamp, value);

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

    function enableAsset(address oracle) public onlyFund {
        require(oracle != address(0), "Invalid oracle address");
        require(oracle != address(this), "Cannot enable self");
        require(oracle != address(fund), "Cannot enable fund");

        oracles.add(oracle);

        emit AssetEnabled(oracle);
    }

    function disableAsset(address oracle) public onlyFund {
        oracles.remove(oracle);

        emit AssetDisabled(oracle);
    }
}
