// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@safe-contracts/handler/TokenCallbackHandler.sol";
import "@safe-contracts/handler/HandlerContext.sol";
import "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {IPortfolio} from "@src/interfaces/IPortfolio.sol";
import {IOwnable} from "@src/interfaces/IOwnable.sol";
import "@src/libs/Errors.sol";
import {POSITION_OPENER_ROLE, POSITION_CLOSER_ROLE} from "@src/libs/Constants.sol";

/// @dev should only be truly global variables. nothing module specific.
contract FundCallbackHandler is TokenCallbackHandler, HandlerContext, IPortfolio, IOwnable {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public immutable fund;

    EnumerableSet.Bytes32Set private openPositions;
    EnumerableSet.AddressSet private assetsOfInterest;

    mapping(address module => uint256 role) private moduleRoles;

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
        onlyModule
        withRole(POSITION_OPENER_ROLE)
        returns (bool result)
    {
        result = openPositions.add(positionPointer);

        emit PositionOpened(_msgSender(), positionPointer);
    }

    function onPositionClosed(bytes32 positionPointer)
        external
        onlyModule
        withRole(POSITION_CLOSER_ROLE)
        returns (bool result)
    {
        result = openPositions.remove(positionPointer);

        emit PositionClosed(_msgSender(), positionPointer);
    }

    function holdsPosition(bytes32 positionPointer) external view returns (bool) {
        return openPositions.contains(positionPointer);
    }

    function hasOpenPositions() external view returns (bool) {
        return openPositions.length() > 0;
    }

    /// @notice native asset = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF)
    function setAssetOfInterest(address _asset) external onlyFund returns (bool result) {
        result = assetsOfInterest.add(_asset);

        emit AssetOfInterestSet(_asset);
    }

    function removeAssetOfInterest(address _asset) external onlyFund returns (bool result) {
        result = assetsOfInterest.remove(_asset);

        emit AssetOfInterestRemoved(_asset);
    }

    function isAssetOfInterest(address asset) external view returns (bool) {
        return assetsOfInterest.contains(asset);
    }

    function getAssetsOfInterest() external view returns (address[] memory) {
        return assetsOfInterest.values();
    }
}
