// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@src/interfaces/IFund.sol";
import "@src/interfaces/IFundValuationOracle.sol";
import "@openzeppelin-contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";

import "@src/oracles/OracleStructs.sol";

contract FundValuationOracle is IFundValuationOracle {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    event AssetEnabled(address asset, address oracle);
    event AssetDisabled(address asset, address oracle);

    IFund public immutable fund;
    uint8 public immutable override decimals;

    EnumerableMap.AddressToUintMap private assetToOracle;
    ValuationHistory private valuations;

    constructor(address fund_, uint8 decimals_) {
        fund = IFund(fund_);
        decimals = decimals_;
    }

    modifier onlyFund() {
        require(msg.sender == address(fund), "Only fund can call this function");
        _;
    }

    /// @dev returned timestamp is average of all oracles. caller can check `block.timestamp` externally.
    /// @dev all sub oracle valuations must be denominated in the same currency
    function getValuation() public returns (uint256 fundValuation, uint256 valuationTimestamp) {
        // check if fund has an open positions
        require(!fund.hasOpenPositions(), "Fund has open positions");

        /// TODO: make sure L2 sequencer is running!

        // get fund balance of each asset that is to be valuated
        // get USD price of each asset from oracle
        uint256 length = assetToOracle.length();
        for (uint256 i = 0; i < length;) {
            (, uint256 _oracle) = assetToOracle.at(i);
            IOracle oracle = IOracle(address(uint160(_oracle)));
            ERC20 asset = ERC20(oracle.asset());

            // weakly enforce oracle be denominated in same currency as fund oracle
            // important!! this does not guarantee that the oracle is denominated in the same currency as the fund
            require(oracle.decimals() == decimals, "Oracle decimal mismatch");

            // get balance of asset in fund
            uint256 balance = asset.balanceOf(address(fund));

            // get asset price from oracle
            (uint256 price, uint256 _timestamp) = oracle.getValuation();

            // calculate the asset value. (nominals * price)
            uint256 assetValuation = balance * price / (10 ** asset.decimals());

            // sum up the USD value of each asset
            fundValuation += assetValuation;

            // we will also sum the timestamps of each oracle
            valuationTimestamp += _timestamp;

            // wont ever overflow
            unchecked {
                ++i;
            }
        }

        // lets get the average timestamp
        valuationTimestamp /= length;

        _insertValuation(fundValuation, valuationTimestamp);
    }

    function asset() public view returns (address) {
        return address(fund);
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

    function getAssetOracle(address asset) public view returns (address) {
        return address(uint160(assetToOracle.get(asset)));
    }

    function enableAsset(address asset, address oracle) public onlyFund {
        require(oracle != address(0), "Invalid oracle address");
        require(oracle != address(this), "Cannot enable self");
        require(oracle != address(fund), "Cannot enable fund");
        require(oracle != asset, "Cannot enable asset as oracle");
        require(asset != address(0), "Invalid oracle address");
        require(asset != address(this), "Cannot enable self");
        require(asset != address(fund), "Cannot enable fund");
        require(IOracle(oracle).asset() == asset, "Oracle asset mismatch");

        require(assetToOracle.set(asset, uint256(uint160(oracle))), "asset enabled");

        emit AssetEnabled(asset, oracle);
    }

    function disableAsset(address asset) public onlyFund {
        address oracle = address(uint160(assetToOracle.get(asset)));

        require(assetToOracle.remove(asset), "Asset not enabled");

        emit AssetDisabled(asset, oracle);
    }
}
