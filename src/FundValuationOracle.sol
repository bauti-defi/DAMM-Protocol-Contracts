// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@src/interfaces/IPortfolio.sol";
import "@src/interfaces/IFundValuationOracle.sol";
import "@openzeppelin-contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";

contract FundValuationOracle is IFundValuationOracle {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    event AssetEnabled(address asset, address oracle);
    event AssetDisabled(address asset, address oracle);

    IPortfolio public immutable fund;
    uint8 public immutable override decimals;

    EnumerableMap.AddressToUintMap private assetToOracle;

    constructor(address fund_, uint8 decimals_) {
        fund = IPortfolio(fund_);
        decimals = decimals_;
    }

    modifier onlyFund() {
        require(msg.sender == address(fund), "Only fund can call this function");
        _;
    }

    /// @dev returned timestamp is average of all oracles. caller can check `block.timestamp` externally.
    /// @dev all sub oracle valuations must be denominated in the same currency
    function getValuation()
        external
        view
        override
        returns (uint256 fundValuation, uint256 valuationTimestamp)
    {
        // check if fund has an open positions
        require(!fund.hasOpenPositions(), "Fund valuable not allowed: open positions");

        /// TODO: make sure L2 sequencer is running!

        // get fund balance of each asset that is to be valuated
        // get USD price of each asset from oracle
        uint256 length = assetToOracle.length();
        for (uint256 i = 0; i < length;) {
            (, uint256 _oracle) = assetToOracle.at(i);
            IOracle oracle = IOracle(address(uint160(_oracle)));
            ERC20 _asset = ERC20(oracle.asset());

            // weakly enforce oracle be denominated in same currency as fund oracle
            // important!! this does not guarantee that the oracle is denominated in the same currency as the fund
            require(oracle.decimals() == decimals, "Oracle decimal mismatch");

            // get balance of asset in fund
            uint256 balance = _asset.balanceOf(address(fund));

            // get asset price from oracle
            (uint256 price, uint256 _timestamp) = oracle.getValuation();

            // calculate the asset value. (nominals * price)
            uint256 assetValuation = balance * price / (10 ** _asset.decimals());

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
    }

    function asset() public view returns (address) {
        return address(fund);
    }

    function getAssetOracle(address asset_) public view returns (address) {
        return address(uint160(assetToOracle.get(asset_)));
    }

    function enableAsset(address asset_, address oracle_) public onlyFund {
        require(oracle_ != address(0), "Invalid oracle address");
        require(oracle_ != address(this), "Cannot enable self");
        require(oracle_ != address(fund), "Cannot enable fund");
        require(oracle_ != asset_, "Cannot enable asset as oracle");
        require(asset_ != address(0), "Invalid oracle address");
        require(asset_ != address(this), "Cannot enable self");
        require(asset_ != address(fund), "Cannot enable fund");
        require(IOracle(oracle_).asset() == asset_, "Oracle asset mismatch");

        require(assetToOracle.set(asset_, uint256(uint160(oracle_))), "asset enabled");

        emit AssetEnabled(asset_, oracle_);
    }

    function disableAsset(address asset_) public onlyFund {
        address oracle = address(uint160(assetToOracle.get(asset_)));

        require(assetToOracle.remove(asset_), "Asset not enabled");

        emit AssetDisabled(asset_, oracle);
    }
}
