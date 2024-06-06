// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@safe-contracts/handler/TokenCallbackHandler.sol";
import "@safe-contracts/handler/HandlerContext.sol";
import "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {IPortfolio} from "@src/interfaces/IPortfolio.sol";
import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";

event PositionOpened(address indexed by, bytes32 positionPointer);

event PositionClosed(address indexed by, bytes32 positionPointer);

error NotModule();

error NotAuthorized();

error OnlyFund();

uint256 constant NULL = 1 << 0;
uint256 constant FUND = 1 << 1;
uint256 constant POSITION_OPENER = 1 << 2;
uint256 constant POSITION_CLOSER = 1 << 3;

/// @dev should only be truly global variables. nothing module specific.
contract FundCallbackHandler is OwnableRoles, TokenCallbackHandler, HandlerContext, IPortfolio {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public immutable fund;

    EnumerableSet.Bytes32Set private openPositions;
    EnumerableSet.AddressSet private assetsOfInterest;

    mapping(address module => uint256 role) private moduleRoles;

    constructor(address _fund) {
        // fallback needs to be owner because OwnableRoles is not aware of the msg.sender passed along by _msgSender()
        _initializeOwner(address(this));
        fund = _fund;

        _grantRoles(_fund, FUND);
    }

    modifier onlyModule() {
        if (!ISafe(fund).isModuleEnabled(_msgSender())) revert NotModule();
        _;
    }

    modifier withRole(uint256 role) {
        if (rolesOf(_msgSender()) & role != role) revert NotAuthorized();
        _;
    }

    modifier onlyFund() {
        if (_msgSender() != fund) revert OnlyFund();
        _;
    }

    function grantRoles(address account, uint256 roles) public payable override onlyFund {
        _grantRoles(account, roles);
    }

    function onPositionOpened(bytes32 positionPointer)
        external
        onlyModule
        returns (
            // withRole(POSITION_OPENER)
            bool result
        )
    {
        result = openPositions.add(positionPointer);

        emit PositionOpened(msg.sender, positionPointer);
    }

    function onPositionClosed(bytes32 positionPointer)
        external
        onlyModule
        returns (
            // withRole(POSITION_CLOSER)
            bool result
        )
    {
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

    /// @notice native asset = address(0)
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
