// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IOracle {
    function getValuationInUSD() external returns (uint256 valuation, uint256 timestamp);

    // function getLatestValuation() external view returns (uint256 valuation, uint256 timestamp);

    // function getValuationCount() external view returns (uint256);

    // function getValuation(uint256 index) external view returns (uint256 valuation, uint256 timestamp);

    function asset() external view returns (address);

    function decimals() external view returns (uint8);
}
