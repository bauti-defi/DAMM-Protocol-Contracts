// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

/// @notice Interface for solady's Ownable.sol
interface IOwnableState {
    /// @dev Returns the owner of the contract.
    function owner() external view returns (address);

    /// @dev Returns the expiry timestamp for the two-step ownership handover to `pendingOwner`.
    function ownershipHandoverExpiresAt(address pendingOwner) external view returns (uint256);
}
