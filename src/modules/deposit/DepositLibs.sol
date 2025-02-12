// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {Errors} from "@src/libs/Errors.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import {
    BrokerAccountInfo,
    AccountState,
    AssetPolicy,
    Broker,
    DepositOrder,
    DepositIntent,
    WithdrawOrder,
    WithdrawIntent
} from "./Structs.sol";
import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";

/// @title Deposit Libraries
/// @notice Collection of helper functions for deposit and withdrawal validation
/// @dev Used to validate intents, check permissions, and verify account states
library DepositLibs {
    using SignatureChecker for address;
    using SafeTransferLib for ERC20;

    bytes32 public constant _DEPOSIT_ORDER_TYPEHASH = keccak256(
        "DepositOrder(uint256 accountId,uint256 amount,uint256 deadline,uint256 minSharesOut,address recipient,address asset,address minter,uint16 referralCode)"
    );

    bytes32 public constant _DEPOSIT_INTENT_TYPEHASH = keccak256(
        "DepositIntent(DepositOrder deposit,uint256 chainId,uint256 relayerTip,uint256 bribe,uint256 nonce)DepositOrder(uint256 accountId,uint256 amount,uint256 deadline,uint256 minSharesOut,address recipient,address asset,address minter,uint16 referralCode)"
    );

    bytes32 public constant _WITHDRAW_ORDER_TYPEHASH = keccak256(
        "WithdrawOrder(uint256 accountId,uint256 shares,uint256 deadline,uint256 minAmountOut,address to,address burner,address asset,uint16 referralCode)"
    );

    bytes32 public constant _WITHDRAW_INTENT_TYPEHASH = keccak256(
        "WithdrawIntent(WithdrawOrder withdraw,uint256 chainId,uint256 relayerTip,uint256 bribe,uint256 nonce)WithdrawOrder(uint256 accountId,uint256 shares,uint256 deadline,uint256 minAmountOut,address to,address burner,address asset,uint16 referralCode)"
    );

    /// @notice Hashes a deposit order for signature verification
    /// @dev Uses EIP-712 typed data hashing
    /// @param order The deposit order to hash
    /// @return The EIP-712 compliant hash of the deposit order
    function hashDepositOrder(DepositOrder memory order) internal pure returns (bytes32) {
        return keccak256(abi.encode(_DEPOSIT_ORDER_TYPEHASH, order));
    }

    /// @notice Hashes a deposit intent for signature verification
    /// @dev Combines deposit order hash with additional intent parameters
    /// @param intent The deposit intent to hash
    /// @return The EIP-712 compliant hash of the deposit intent
    function hashDepositIntent(DepositIntent memory intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _DEPOSIT_INTENT_TYPEHASH,
                hashDepositOrder(intent.deposit),
                intent.chainId,
                intent.relayerTip,
                intent.bribe,
                intent.nonce
            )
        );
    }

    /// @notice Hashes a withdrawal order for signature verification
    /// @dev Uses EIP-712 typed data hashing
    /// @param order The withdrawal order to hash
    /// @return The EIP-712 compliant hash of the withdrawal order
    function hashWithdrawOrder(WithdrawOrder memory order) internal pure returns (bytes32) {
        return keccak256(abi.encode(_WITHDRAW_ORDER_TYPEHASH, order));
    }

    /// @notice Hashes a withdrawal intent for signature verification
    /// @dev Combines withdrawal order hash with additional intent parameters
    /// @param intent The withdrawal intent to hash
    /// @return The EIP-712 compliant hash of the withdrawal intent
    function hashWithdrawIntent(WithdrawIntent memory intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _WITHDRAW_INTENT_TYPEHASH,
                hashWithdrawOrder(intent.withdraw),
                intent.chainId,
                intent.relayerTip,
                intent.bribe,
                intent.nonce
            )
        );
    }

    /// @notice Validates a deposit/withdraw intent signature, nonce, and chain ID
    /// @dev Reverts if any validation check fails
    /// @param intentHash The hash of the intent to validate
    /// @param signature The signature to verify
    /// @param signer The expected signer of the intent
    /// @param blockId The expected chain ID
    /// @param nonce The nonce from the intent
    /// @param expectedNonce The expected nonce value
    function validateIntent(
        bytes32 intentHash,
        bytes memory signature,
        address signer,
        uint256 blockId,
        uint256 nonce,
        uint256 expectedNonce
    ) internal view {
        if (!SignatureChecker.isValidSignatureNow(signer, intentHash, signature)) {
            revert Errors.Deposit_InvalidSignature();
        }
        if (nonce != expectedNonce) revert Errors.Deposit_InvalidNonce();
        if (blockId != block.chainid) revert Errors.Deposit_InvalidChain();
    }

    /// @notice Transfers tokens if amount is greater than zero
    /// @dev Uses SafeTransferLib for safe token transfers
    /// @param token The ERC20 token to transfer
    /// @param recipient The recipient of the tokens
    /// @param amount The amount to transfer
    function pay(ERC20 token, address recipient, uint256 amount) internal {
        if (amount > 0) token.safeTransfer(recipient, amount);
    }

    /// @notice Generates a unique pointer for broker asset policies
    /// @dev Used as key in broker.assetPolicy mapping
    /// @param asset The asset address
    /// @param isDeposit Whether this is for a deposit (true) or withdrawal (false)
    /// @return The unique pointer for the asset policy
    function brokerAssetPolicyPointer(address asset, bool isDeposit)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(asset, isDeposit));
    }

    /// @notice Checks if a broker account is in ACTIVE state
    /// @param account The broker account to check
    /// @return True if account is active
    function isActive(BrokerAccountInfo memory account) internal pure returns (bool) {
        return account.state == AccountState.ACTIVE;
    }

    /// @notice Checks if a broker account is in PAUSED state
    /// @param account The broker account to check
    /// @return True if account is paused
    function isPaused(BrokerAccountInfo memory account) internal pure returns (bool) {
        return account.state == AccountState.PAUSED;
    }

    /// @notice Checks if a broker account can be closed
    /// @dev Account must be either ACTIVE or PAUSED to be closed
    /// @param account The broker account to check
    /// @return True if account can be closed
    function canBeClosed(BrokerAccountInfo memory account) internal pure returns (bool) {
        return account.state == AccountState.ACTIVE || account.state == AccountState.PAUSED;
    }

    /// @notice Checks if a broker account has expired
    /// @dev Account is expired if expirationTimestamp is non-zero and has passed
    /// @param account The broker account to check
    /// @return True if account has expired
    function isExpired(BrokerAccountInfo memory account) internal view returns (bool) {
        return account.expirationTimestamp != 0 && block.timestamp >= account.expirationTimestamp;
    }
}
