// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

struct DepositIntent {
    address user;
    address asset;
    uint256 chaindId;
    uint256 amount;
    uint256 deadline;
    uint256 minSharesOut;
    uint256 relayerTip;
    uint256 nonce;
}

struct DepositOrder {
    DepositIntent intent;
    bytes signature;
}

struct WithdrawIntent {
    address user;
    address to;
    address asset;
    uint256 chaindId;
    uint256 shares;
    uint256 deadline;
    uint256 minAmountOut;
    uint256 relayerTip;
    uint256 nonce;
}

struct WithdrawOrder {
    WithdrawIntent intent;
    bytes signature;
}

enum Role {
    NONE,
    /// default
    USER,
    SUPER_USER
}

enum AccountStatus {
    NULL,
    ACTIVE,
    PAUSED
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
    uint256 nonce;
    Role role;
    AccountStatus status;
}
