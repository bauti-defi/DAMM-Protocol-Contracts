// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {IDepositModule} from "./IDepositModule.sol";

interface IWhitelistDepositModule is IDepositModule {
    /// @notice Emitted when a user is added to the whitelist
    /// @param user_ The user address that was added
    event UserAddedToWhitelist(address user_);

    /// @notice Emitted when a user is removed from the whitelist
    /// @param user_ The user address that was removed
    event UserRemovedFromWhitelist(address user_);

    /// @notice Checks if a user is whitelisted
    /// @param user_ The user address to check
    /// @return True if user is whitelisted
    function userWhitelist(address user_) external view returns (bool);

    /// @notice Adds a user to the whitelist
    /// @dev Only callable by admin
    /// @param user_ The user address to whitelist
    function addUserToWhitelist(address user_) external;

    /// @notice Removes a user from the whitelist
    /// @dev Only callable by admin
    /// @param user_ The user address to remove
    function removeUserFromWhitelist(address user_) external;
}
