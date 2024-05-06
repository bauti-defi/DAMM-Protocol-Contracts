// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@src/interfaces/IFund.sol";
import "@src/interfaces/IOracle.sol";
import "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

contract FundValuationOracle is IOracle {
    using EnumerableSet for EnumerableSet.AddressSet;

    IFund public immutable fund;

    EnumerableSet.AddressSet private oracles;

    constructor(address fund_) {
        fund = IFund(fund_);
    }

    modifier onlyFund() {
        require(msg.sender == address(fund), "Only fund can call this function");
        _;
    }

    function getValuationInUSD() public view returns (uint256 valuation) {
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
            uint256 price = oracle.getValuationInUSD();
            uint8 decimals = oracle.decimals();

            // sum up the USD value of each asset
            valuation += balance * price / 10 ** decimals;

            unchecked {
                ++i;
            }
        }

        // sum up the USD value of each asset
        return valuation;
    }

    function asset() public view returns (address) {
        return address(fund);
    }

    /// TODO: make sure this is same as USD oracles
    function decimals() public view returns (uint8) {
        return 8;
    }

    function enableAsset(address oracle) public onlyFund {
        require(oracle != address(0), "Invalid oracle address");
        require(oracle != address(this), "Cannot enable self");
        require(oracle != address(fund), "Cannot enable fund");

        oracles.add(oracle);
    }

    function disableAsset(address oracle) public onlyFund {
        oracles.remove(oracle);
    }
}
