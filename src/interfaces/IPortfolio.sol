// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IPortfolio {
    event AssetOfInterestSet(address indexed asset);

    event AssetOfInterestRemoved(address indexed asset);

    event PositionOpened(address indexed by, bytes32 positionPointer);

    event PositionClosed(address indexed by, bytes32 positionPointer);

    function onPositionOpened(bytes32 positionId) external returns (bool);

    function onPositionClosed(bytes32 positionId) external returns (bool);

    function hasOpenPositions() external view returns (bool);

    function holdsPosition(bytes32 positionPointer) external view returns (bool);

    function setAssetOfInterest(address _asset) external returns (bool);

    function removeAssetOfInterest(address _asset) external returns (bool);

    function isAssetOfInterest(address asset) external view returns (bool);

    function getAssetsOfInterest() external view returns (address[] memory);
}
