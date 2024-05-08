// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./IOracle.sol";

interface IFundValuationOracle is IOracle {
    function getAssetOracle(address asset) external view returns (address oracle);

    function enableAsset(address asset, address oracle) external;

    function disableAsset(address asset) external;
}
