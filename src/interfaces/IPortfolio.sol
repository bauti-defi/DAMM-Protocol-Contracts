// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/// @title IPortfolio
/// @notice Interface for managing fund positions and tracked assets
interface IPortfolio {

    /// @notice Emitted when a new position is opened
    /// @param by Address of the module that opened the position
    /// @param positionPointer Unique identifier for the position
    event PositionOpened(address indexed by, bytes32 positionPointer);

    /// @notice Emitted when a position is closed
    /// @param by Address of the module that closed the position
    /// @param positionPointer Unique identifier for the position
    /// @param fundLiquidated True if this was the last open position
    event PositionClosed(address indexed by, bytes32 positionPointer, bool fundLiquidated);

    /// @notice Records a new position opening
    /// @param positionId Unique identifier for the position
    /// @return False if position was already open, true if successfully added
    function onPositionOpened(bytes32 positionId) external returns (bool);

    /// @notice Records a position closing
    /// @param positionId Unique identifier for the position
    /// @return False if position was already closed, true if successfully removed
    function onPositionClosed(bytes32 positionId) external returns (bool);

    /// @notice Checks if the fund has any open positions
    /// @return True if there is at least one open position
    function hasOpenPositions() external view returns (bool);

    /// @notice Checks if a specific position is currently open
    /// @param positionPointer Unique identifier for the position
    /// @return True if the position exists in the open positions set
    function holdsPosition(bytes32 positionPointer) external view returns (bool);

    /// @notice Gets the block number of the most recent liquidation
    /// @return Block number of last liquidation, or -1 if never liquidated
    function getLatestLiquidationBlock() external view returns (int256);

    /// @notice Returns the complete history of liquidation events
    /// @return Array of block numbers when the fund was fully liquidated
    function getFundLiquidationTimeSeries() external view returns (uint256[] memory);
}
