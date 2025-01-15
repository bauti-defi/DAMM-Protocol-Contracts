// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@safe-contracts/handler/TokenCallbackHandler.sol";
import "@safe-contracts/handler/HandlerContext.sol";
import "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {IPortfolio} from "@src/interfaces/IPortfolio.sol";
import {IOwnable} from "@src/interfaces/IOwnable.sol";
import {IMotherFund} from "@src/interfaces/IMotherFund.sol";
import "@src/libs/Errors.sol";
import {POSITION_OPENER_ROLE, POSITION_CLOSER_ROLE} from "@src/libs/Constants.sol";

event Paused();

event Unpaused();

/// @dev should only be truly global variables.
contract FundCallbackHandler is
    TokenCallbackHandler,
    HandlerContext,
    IPortfolio,
    IMotherFund,
    IOwnable
{
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public immutable fund;

    EnumerableSet.Bytes32Set private openPositions;
    EnumerableSet.AddressSet private assetsToValuate;
    EnumerableSet.AddressSet private childFunds;

    mapping(address module => uint256 role) private moduleRoles;
    bool public paused;

    /// @dev Ordered time series of blocks the fund was liquidated at
    /// can be used for external inference
    uint256[] private fundLiquidationTimeSeries;

    constructor(address _fund) {
        fund = _fund;
    }

    modifier onlyModule() {
        if (!ISafe(fund).isModuleEnabled(_msgSender())) revert Errors.Fund_NotModule();
        _;
    }

    modifier withRole(uint256 roles) {
        if (moduleRoles[_msgSender()] & roles != roles) revert Errors.Fund_NotAuthorized();
        _;
    }

    modifier onlyFund() {
        if (_msgSender() != fund) revert Errors.OnlyFund();
        _;
    }

    function grantRoles(address module, uint256 roles) external override onlyFund {
        moduleRoles[module] = roles;

        emit RolesGranted(module, roles);
    }

    function hasAllRoles(address module, uint256 roles) external view override returns (bool) {
        return moduleRoles[module] & roles == roles;
    }

    function onPositionOpened(bytes32 positionPointer)
        external
        override
        onlyModule
        withRole(POSITION_OPENER_ROLE)
        returns (bool result)
    {
        /// @notice returns false if position is already open
        result = openPositions.add(positionPointer);

        if (result) emit PositionOpened(_msgSender(), positionPointer);
    }

    function onPositionClosed(bytes32 positionPointer)
        external
        override
        onlyModule
        withRole(POSITION_CLOSER_ROLE)
        returns (bool result)
    {
        /// @notice returns false if position is already closed
        result = openPositions.remove(positionPointer);

        bool liquidated = openPositions.length() == 0 && result;
        if (liquidated) {
            fundLiquidationTimeSeries.push(block.number);
        }

        if (result) emit PositionClosed(_msgSender(), positionPointer, liquidated);
    }

    function holdsPosition(bytes32 positionPointer) external view override returns (bool) {
        return openPositions.contains(positionPointer);
    }

    function hasOpenPositions() external view override returns (bool) {
        return openPositions.length() > 0;
    }

    function getLatestLiquidationBlock() external view override returns (int256) {
        uint256 length = fundLiquidationTimeSeries.length;

        if (length == 0) return -1;

        return int256(fundLiquidationTimeSeries[length - 1]);
    }

    function getFundLiquidationTimeSeries() external view override returns (uint256[] memory) {
        return fundLiquidationTimeSeries;
    }

    /// @notice native asset = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
    function setAssetToValuate(address _asset) external override onlyFund returns (bool result) {
        result = assetsToValuate.add(_asset);

        if (result) emit AssetOfInterestSet(_asset);
    }

    function removeAssetToValuate(address _asset)
        external
        override
        onlyFund
        returns (bool result)
    {
        result = assetsToValuate.remove(_asset);

        if (result) emit AssetToValuateRemoved(_asset);
    }

    function isAssetToValuate(address asset) external view override returns (bool) {
        return assetsToValuate.contains(asset);
    }

    function getAssetsToValuate() external view override returns (address[] memory) {
        return assetsToValuate.values();
    }

    function getChildFunds() external view override returns (address[] memory) {
        return childFunds.values();
    }

    function addChildFund(address _childFund) external override onlyFund returns (bool) {
        return childFunds.add(_childFund);
    }

    function removeChildFund(address _childFund) external override onlyFund returns (bool) {
        return childFunds.remove(_childFund);
    }

    function isChildFund(address _childFund) external view override returns (bool) {
        return childFunds.contains(_childFund);
    }

    function pause() external onlyFund {
        paused = true;

        emit Paused();
    }

    function unpause() external onlyFund {
        paused = false;

        emit Unpaused();
    }
}
