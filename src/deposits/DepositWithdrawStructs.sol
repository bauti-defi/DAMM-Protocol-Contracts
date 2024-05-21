// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

struct AssetPolicy {
    uint256 minNominalDeposit;
    uint256 minNominalWithdrawal;
    bool canDeposit;
    bool canWithdraw;
    bool permissioned;
    bool enabled;
}

struct DepositIntent {
    address user;
    address to;
    address asset;
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
    uint256 amount;
    uint256 deadline;
    uint256 maxSharesIn;
    uint256 relayerTip;
    uint256 nonce;
}

struct WithdrawOrder {
    WithdrawIntent intent;
    bytes signature;
}

enum Role {
    NONE, // default
    USER,
    SUPER_USER
}
