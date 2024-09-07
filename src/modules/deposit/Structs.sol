// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

struct DepositIntent {
    DepositOrder deposit;
    uint256 chaindId;
    uint256 relayerTip;
    uint256 nonce;
}

struct DepositOrder {
    uint256 accountId;
    address recipient;
    address asset;
    uint256 amount;
    uint256 deadline;
    uint256 minSharesOut;
}

struct SignedDepositIntent {
    DepositIntent intent;
    bytes signature;
}

struct WithdrawOrder {
    uint256 accountId;
    address to;
    address asset;
    uint256 shares;
    uint256 deadline;
    uint256 minAmountOut;
}

struct WithdrawIntent {
    WithdrawOrder withdraw;
    uint256 chaindId;
    uint256 relayerTip;
    uint256 nonce;
}

struct SignedWithdrawIntent {
    WithdrawIntent intent;
    bytes signature;
}

enum Role {
    NONE,
    /// default
    USER,
    SUPER_USER
}

enum AccountState {
    NULL,
    ACTIVE,
    PAUSED,
    CLOSED
}

struct AssetPolicy {
    uint256 minimumDeposit;
    uint256 minimumWithdrawal;
    bool canDeposit;
    bool canWithdraw;
    bool permissioned;
    bool enabled;
}

struct UserAccountInfo {
    Role role;
    AccountState state;
    uint256 expirationTimestamp;
    uint256 nonce;
    uint256 shareMintLimit;
    uint256 sharesMinted;
}

struct CreateAccountParams {
    uint256 ttl;
    uint256 shareMintLimit;
    address user;
    Role role;
}

library AccountLib {
    function isActive(UserAccountInfo memory account) internal pure returns (bool) {
        return account.state == AccountState.ACTIVE;
    }

    function isPaused(UserAccountInfo memory account) internal pure returns (bool) {
        return account.state == AccountState.PAUSED;
    }

    function canBeClosed(UserAccountInfo memory account) internal pure returns (bool) {
        return account.state == AccountState.ACTIVE || account.state == AccountState.PAUSED;
    }

    function isSuperUser(UserAccountInfo memory account) internal pure returns (bool) {
        return account.role == Role.SUPER_USER;
    }

    function isExpired(UserAccountInfo memory account) internal view returns (bool) {
        return account.expirationTimestamp != 0 && block.timestamp >= account.expirationTimestamp;
    }
}

using AccountLib for UserAccountInfo global;
