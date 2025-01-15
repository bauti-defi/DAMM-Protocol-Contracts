// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

/// @title IPauser
/// @notice Interface for managing pause functionality at both global and target-specific levels
interface IPauser {
    /// @notice Emitted when a specific target is paused
    /// @param target Address of the target that was paused
    event Paused(address target);

    /// @notice Emitted when a specific target is unpaused
    /// @param target Address of the target that was unpaused
    event Unpaused(address target);

    /// @notice Emitted when the global pause is activated
    event GlobalPaused();

    /// @notice Emitted when the global pause is deactivated
    event GlobalUnpaused();

    /// @notice Checks if operations are paused for a specific caller
    /// @param caller Address to check pause status for
    /// @return True if either global pause is active or caller is specifically paused
    function paused(address caller) external returns (bool);

    /// @notice Pauses operations for a specific target
    /// @param target Address to pause
    function pause(address target) external;

    /// @notice Unpauses operations for a specific target
    /// @param target Address to unpause
    function unpause(address target) external;

    /// @notice Pauses all operations globally
    function pauseGlobal() external;

    /// @notice Unpauses all operations globally
    function unpauseGlobal() external;
}
