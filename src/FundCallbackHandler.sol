// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@safe-contracts/handler/TokenCallbackHandler.sol";
import "@safe-contracts/handler/HandlerContext.sol";
import "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {IPortfolio} from "@src/interfaces/IPortfolio.sol";

event PositionOpened(address indexed by, bytes32 positionPointer);

event PositionClosed(address indexed by, bytes32 positionPointer);

error NotModule();

error OnlyFund();

/// @dev concept under development!
contract FundCallbackHandler is TokenCallbackHandler, HandlerContext, IPortfolio {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public immutable fund;

    /// could be used to hold fund specific state
    /// for example, registry of open positions, allowed tokens
    /// maybe hook registry needs to go here?
    /// maybe pause state should go here?
    /// maybe only global state should go here?

    /// should only be truly global variables. nothing module specific.
    /// `pause` is a good place to start
    /// hooks registry here would be a bad idea

    EnumerableSet.Bytes32Set private openPositions;
    EnumerableSet.AddressSet private assetsOfInterest;

    constructor(address _fund) {
        fund = _fund;
    }

    /// TODO: Allow scoping of module
    modifier onlyModule() {
        if (!ISafe(fund).isModuleEnabled(msg.sender)) revert NotModule();
        _;
    }

    modifier onlyFund() {
        if (_msgSender() != fund) revert OnlyFund();
        _;
    }

    function onPositionOpened(bytes32 positionPointer) external onlyModule returns (bool result) {
        result = openPositions.add(positionPointer);

        emit PositionOpened(msg.sender, positionPointer);
    }

    function onPositionClosed(bytes32 positionPointer) external onlyModule returns (bool result) {
        result = openPositions.remove(positionPointer);

        emit PositionClosed(msg.sender, positionPointer);
    }

    function holdsPosition(bytes32 positionPointer) external view returns (bool) {
        return openPositions.contains(positionPointer);
    }

    function hasOpenPositions() external view returns (bool) {
        return openPositions.length() > 0;
    }

    function setAssetsOfInterest(address[] calldata _assets)
        external
        onlyFund
        returns (bool result)
    {
        for (uint256 i = 0; i < _assets.length; i++) {
            result = assetsOfInterest.add(_assets[i]);
        }
    }

    function addAssetOfInterest(address _asset) external onlyFund returns (bool result) {
        result = assetsOfInterest.add(_asset);
    }

    function removeAssetsOfInterest(address[] calldata _assets)
        external
        onlyFund
        returns (bool result)
    {
        for (uint256 i = 0; i < _assets.length; i++) {
            result = assetsOfInterest.remove(_assets[i]);
        }
    }

    function removeAssetOfInterest(address _asset) external onlyFund returns (bool result) {
        result = assetsOfInterest.remove(_asset);
    }

    function isAssetOfInterest(address asset) external view returns (bool) {
        return assetsOfInterest.contains(asset);
    }

    function getAssetsOfInterest() external view returns (address[] memory) {
        return assetsOfInterest.values();
    }
}
