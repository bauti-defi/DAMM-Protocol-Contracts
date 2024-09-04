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
    AccountState status;
    uint256 expirationTimestamp;
    uint256 nonce;
}
