// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "@safe-contracts/handler/TokenCallbackHandler.sol";
import "@safe-contracts/handler/HandlerContext.sol";
import "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {IPortfolio} from "@src/interfaces/IPortfolio.sol";
import {IOwnable} from "@src/interfaces/IOwnable.sol";
import {IMotherFund} from "@src/interfaces/IMotherFund.sol";
import {IPauser} from "@src/interfaces/IPauser.sol";
import "@src/libs/Errors.sol";
import {POSITION_OPENER_ROLE, POSITION_CLOSER_ROLE, PAUSER_ROLE} from "@src/libs/Constants.sol";

/**
 * @title FundCallbackHandler
 * @notice A fallback handler contract for Safe-based investment funds that manages positions, assets,
 *         and permissions
 * @dev This contract serves as the central authority for a fund by:
 *      - Managing fund positions and tracking their lifecycle
 *      - Tracking assets that need valuation
 *      - Managing child funds in a parent-child relationship
 *      - Controlling module permissions through role-based access
 *      - Implementing pause functionality for security
 *      - Recording liquidation events for on-chain analysis
 *
 */
contract FundCallbackHandler is
    TokenCallbackHandler,
    HandlerContext,
    IPortfolio,
    IMotherFund,
    IPauser,
    IOwnable
{
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice The Safe contract address that this handler is attached to
    address public immutable fund;

    /// @notice Set of position identifiers that are currently open
    /// @dev Uses bytes32 for flexible position identification across different protocols
    EnumerableSet.Bytes32Set private openPositions;

    /// @notice Set of child fund addresses managed by this fund
    EnumerableSet.AddressSet private childFunds;

    /// @notice Maps module addresses to their assigned roles bitmap
    /// @dev Roles are represented as bits in a uint256, allowing multiple roles per module
    mapping(address module => uint256 role) private moduleRoles;

    /// @notice Maps target addresses to their paused state
    mapping(address target => bool paused) private pausedTargets;

    /// @notice Global pause state that affects all operations
    bool private globalPause;

    /// @notice Ordered time series of block numbers when the fund was fully liquidated
    /// @dev A fund is considered liquidated when all positions are closed
    uint256[] private fundLiquidationTimeSeries;

    constructor(address _fund) {
        fund = _fund;
    }

    /// @notice Ensures caller is an enabled module on the fund
    modifier onlyModule() {
        if (!ISafe(fund).isModuleEnabled(_msgSender())) revert Errors.Fund_NotModule();
        _;
    }

    /// @notice Ensures caller has all specified roles
    /// @param roles Bitmap of required roles
    modifier withRole(uint256 roles) {
        if (moduleRoles[_msgSender()] & roles != roles) revert Errors.Fund_NotAuthorized();
        _;
    }

    /// @notice Ensures caller is the fund itself
    modifier onlyFund() {
        if (_msgSender() != fund) revert Errors.OnlyFund();
        _;
    }

    /// @notice Ensures caller is either the fund or has specified roles
    /// @param roles Bitmap of acceptable roles if caller is not the fund
    modifier onlyFundOrRole(uint256 roles) {
        if (_msgSender() != fund && moduleRoles[_msgSender()] & roles != roles) {
            revert Errors.Fund_NotAuthorized();
        }
        _;
    }

    /// @inheritdoc IMotherFund
    function getChildFunds() external view override returns (address[] memory) {
        return childFunds.values();
    }

    /// @inheritdoc IMotherFund
    function addChildFund(address _childFund) external override onlyFund returns (bool) {
        return childFunds.add(_childFund);
    }

    /// @inheritdoc IMotherFund
    function removeChildFund(address _childFund) external override onlyFund returns (bool) {
        return childFunds.remove(_childFund);
    }

    /// @inheritdoc IMotherFund
    function isChildFund(address _childFund) external view override returns (bool) {
        return childFunds.contains(_childFund);
    }

    /// @inheritdoc IPauser
    function paused(address caller) external view override returns (bool) {
        return globalPause || pausedTargets[caller];
    }

    /// @inheritdoc IPauser
    function pause(address target) external onlyFundOrRole(PAUSER_ROLE) {
        pausedTargets[target] = true;
        emit Paused(target);
    }

    /// @inheritdoc IPauser
    function pauseGlobal() external onlyFundOrRole(PAUSER_ROLE) {
        globalPause = true;
        emit GlobalPaused();
    }

    /// @inheritdoc IPauser
    function unpause(address target) external onlyFundOrRole(PAUSER_ROLE) {
        pausedTargets[target] = false;
        emit Unpaused(target);
    }

    /// @inheritdoc IPauser
    function unpauseGlobal() external onlyFundOrRole(PAUSER_ROLE) {
        globalPause = false;
        emit GlobalUnpaused();
    }

    /// @inheritdoc IOwnable
    function grantRoles(address module, uint256 roles) external override onlyFund {
        moduleRoles[module] = roles;
        emit RolesGranted(module, roles);
    }

    /// @inheritdoc IOwnable
    function hasAllRoles(address module, uint256 roles) external view override returns (bool) {
        return moduleRoles[module] & roles == roles;
    }

    /// @inheritdoc IPortfolio
    function onPositionOpened(bytes32 positionPointer)
        external
        override
        onlyModule
        withRole(POSITION_OPENER_ROLE)
        returns (bool result)
    {
        result = openPositions.add(positionPointer);
        if (result) emit PositionOpened(_msgSender(), positionPointer);
    }

    /// @inheritdoc IPortfolio
    function onPositionClosed(bytes32 positionPointer)
        external
        override
        onlyModule
        withRole(POSITION_CLOSER_ROLE)
        returns (bool result)
    {
        result = openPositions.remove(positionPointer);

        bool liquidated = openPositions.length() == 0 && result;
        if (liquidated) {
            fundLiquidationTimeSeries.push(block.number);
        }

        if (result) emit PositionClosed(_msgSender(), positionPointer, liquidated);
    }

    /// @inheritdoc IPortfolio
    function holdsPosition(bytes32 positionPointer) external view override returns (bool) {
        return openPositions.contains(positionPointer);
    }

    /// @inheritdoc IPortfolio
    function hasOpenPositions() external view override returns (bool) {
        return openPositions.length() > 0;
    }

    /// @inheritdoc IPortfolio
    function getLatestLiquidationBlock() external view override returns (int256) {
        uint256 length = fundLiquidationTimeSeries.length;
        if (length == 0) return -1;
        return int256(fundLiquidationTimeSeries[length - 1]);
    }

    /// @inheritdoc IPortfolio
    function getFundLiquidationTimeSeries() external view override returns (uint256[] memory) {
        return fundLiquidationTimeSeries;
    }
}
