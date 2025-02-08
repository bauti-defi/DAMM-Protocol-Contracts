// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

/// @notice A deposit intent represents a user's desire to deposit assets into the fund
/// @dev Contains the deposit order details along with incentives for execution
struct DepositIntent {
    DepositOrder deposit; // The core deposit order parameters
    uint256 chaindId; // Chain ID for replay protection
    uint256 relayerTip; // Amount paid to relayer for executing the intent (in deposit asset)
    uint256 bribe; // Amount paid to fund to cover potential rebalancing costs when accepting deposits
    uint256 nonce; // Nonce for replay protection
}

/// @notice Core parameters for a deposit order
/// @dev Used both directly and as part of DepositIntent
struct DepositOrder {
    uint256 accountId; // ID of the broker account
    uint256 amount; // Amount of asset to deposit
    uint256 deadline; // Timestamp after which this order expires
    uint256 minSharesOut; // Minimum acceptable number of shares to receive
    address recipient; // Address to receive the minted shares
    address asset; // Asset being deposited
    address depositor; // Address that is depositing the assets
    uint16 referralCode; // Optional referral code
}

/// @notice A signed deposit intent ready for execution
struct SignedDepositIntent {
    DepositIntent intent; // The deposit intent
    bytes signature; // Signature of the intent
}

/// @notice Core parameters for a withdrawal order
struct WithdrawOrder {
    uint256 accountId; // ID of the broker account
    address to; // Address to receive the withdrawn assets
    address asset; // Asset to withdraw into
    uint256 shares; // Number of shares to burn
    uint256 deadline; // Timestamp after which this order expires
    uint256 minAmountOut; // Minimum acceptable amount of asset to receive
    uint16 referralCode; // Optional referral code
}

/// @notice A withdrawal intent represents a user's desire to withdraw assets from the fund
/// @dev Contains the withdrawal order details along with incentives for execution
struct WithdrawIntent {
    WithdrawOrder withdraw; // The core withdrawal order parameters
    uint256 chaindId; // Chain ID for replay protection
    uint256 relayerTip; // Amount paid to relayer for executing the intent (in withdrawal asset)
    uint256 bribe; // Amount paid to fund to cover potential rebalancing costs when accepting withdrawals
    uint256 nonce; // Nonce for replay protection
}

/// @notice A signed withdrawal intent ready for execution
struct SignedWithdrawIntent {
    WithdrawIntent intent; // The withdrawal intent
    bytes signature; // Signature of the intent
}

/// @notice Possible states for a broker account
enum AccountState {
    NULL, // Default state, not initialized
    ACTIVE, // Account is active and can be used
    PAUSED, // Account is temporarily paused
    CLOSED // Account is permanently closed

}

/// @notice Global policy configuration for an asset
/// @dev Must be enabled along with broker-specific permissions for deposits/withdrawals
struct AssetPolicy {
    uint256 minimumDeposit; // Minimum amount required for deposits
    uint256 minimumWithdrawal; // Minimum amount required for withdrawals
    bool canDeposit; // Whether deposits are allowed
    bool canWithdraw; // Whether withdrawals are allowed
    bool enabled; // Whether this policy is active
}

/// @notice Information about a broker's account
/// @dev Tracks fees, limits, and accounting information
struct BrokerAccountInfo {
    bool transferable; // Whether the broker NFT can be transferred
    AccountState state; // Current state of the account
    address feeRecipient; // Address to receive broker's fees
    uint256 expirationTimestamp; // When the account expires
    uint256 shareMintLimit; // Maximum shares that can be minted
    uint256 cumulativeSharesMinted; // Total shares minted over account lifetime
    uint256 cumulativeUnitsDeposited; // Total units of account deposited
    uint256 totalSharesOutstanding; // Current shares outstanding
    uint256 brokerPerformanceFeeInBps; // Broker's cut of performance fee (basis points)
    uint256 protocolPerformanceFeeInBps; // Protocol's cut of performance fee (basis points)
    uint256 brokerEntranceFeeInBps; // Broker's entrance fee (basis points)
    uint256 protocolEntranceFeeInBps; // Protocol's entrance fee (basis points)
    uint256 brokerExitFeeInBps; // Broker's exit fee (basis points)
    uint256 protocolExitFeeInBps; // Protocol's exit fee (basis points)
    uint256 nonce; // Current nonce for replay protection
}

/// @notice A broker's complete account information
/// @dev Combines account info with asset-specific policies
struct Broker {
    BrokerAccountInfo account; // Core account information
    mapping(bytes32 pointer => bool allowed) assetPolicy; // Asset-specific deposit/withdraw permissions
}

/// @notice Parameters for creating a new broker account
struct CreateAccountParams {
    uint256 ttl; // Time-to-live for the account
    uint256 shareMintLimit; // Maximum shares that can be minted
    uint256 brokerPerformanceFeeInBps; // Broker's performance fee rate
    uint256 protocolPerformanceFeeInBps; // Protocol's performance fee rate
    uint256 brokerEntranceFeeInBps; // Broker's entrance fee rate
    uint256 protocolEntranceFeeInBps; // Protocol's entrance fee rate
    uint256 brokerExitFeeInBps; // Broker's exit fee rate
    uint256 protocolExitFeeInBps; // Protocol's exit fee rate
    address feeRecipient; // Address to receive broker's fees
    address user; // Owner of the broker account
    bool transferable; // Whether the broker NFT can be transferred
}
