// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

struct DepositIntent {
    DepositOrder deposit;
    uint256 chaindId;
    uint256 relayerTip;
    uint256 bribe;
    uint256 nonce;
}

struct DepositOrder {
    uint256 accountId;
    address recipient;
    address asset;
    uint256 amount;
    uint256 deadline;
    uint256 minSharesOut;
    uint16 referralCode;
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
    uint16 referralCode;
}

struct WithdrawIntent {
    WithdrawOrder withdraw;
    uint256 chaindId;
    uint256 relayerTip;
    uint256 bribe;
    uint256 nonce;
}

struct SignedWithdrawIntent {
    WithdrawIntent intent;
    bytes signature;
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
    bool enabled;
}

struct BrokerAccountInfo {
    bool transferable;
    AccountState state;
    address feeRecipient;
    uint256 expirationTimestamp;
    uint256 shareMintLimit;
    uint256 cumulativeSharesMinted;
    uint256 cumulativeUnitsDeposited;
    uint256 totalSharesOutstanding;
    uint256 brokerPerformanceFeeInBps;
    uint256 protocolPerformanceFeeInBps;
    uint256 brokerEntranceFeeInBps;
    uint256 protocolEntranceFeeInBps;
    uint256 brokerExitFeeInBps;
    uint256 protocolExitFeeInBps;
    uint256 nonce;
}

struct Broker {
    BrokerAccountInfo account;
    mapping(bytes32 pointer => bool allowed) assetPolicy;
}

struct CreateAccountParams {
    uint256 ttl;
    uint256 shareMintLimit;
    uint256 brokerPerformanceFeeInBps;
    uint256 protocolPerformanceFeeInBps;
    uint256 brokerEntranceFeeInBps;
    uint256 protocolEntranceFeeInBps;
    uint256 brokerExitFeeInBps;
    uint256 protocolExitFeeInBps;
    address feeRecipient;
    address user;
    bool transferable;
}
