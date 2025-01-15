// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IPortfolio {
    event AssetOfInterestSet(address indexed asset);

    event AssetToValuateRemoved(address indexed asset);

    event PositionOpened(address indexed by, bytes32 positionPointer);

    event PositionClosed(address indexed by, bytes32 positionPointer, bool fundLiquidated);

    function fund() external view returns (address);

    function onPositionOpened(bytes32 positionId) external returns (bool);

    function onPositionClosed(bytes32 positionId) external returns (bool);

    function hasOpenPositions() external view returns (bool);

    function holdsPosition(bytes32 positionPointer) external view returns (bool);

    function getLatestLiquidationBlock() external view returns (int256);

    function getFundLiquidationTimeSeries() external view returns (uint256[] memory);

    function setAssetToValuate(address _asset) external returns (bool);

    function removeAssetToValuate(address _asset) external returns (bool);

    function isAssetToValuate(address asset) external view returns (bool);

    function getAssetsToValuate() external view returns (address[] memory);
}
