// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IOracle {
    function getValuationInUSD() external view returns (uint256 valuation);

    function asset() external view returns (address);

    function decimals() external view returns (uint8);
}
