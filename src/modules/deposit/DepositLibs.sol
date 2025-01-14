// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Errors} from "@src/libs/Errors.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import {BrokerAccountInfo, Role, AccountState, AssetPolicy} from "./Structs.sol";

library DepositLibs {
    using MessageHashUtils for bytes;
    using SignatureChecker for address;

    function validateIntent(
        bytes memory intent,
        bytes memory signature,
        address signer,
        uint256 blockId,
        uint256 nonce,
        uint256 expectedNonce
    ) internal view {
        if (
            !SignatureChecker.isValidSignatureNow(signer, intent.toEthSignedMessageHash(), signature)
        ) revert Errors.Deposit_InvalidSignature();
        if (nonce != expectedNonce) revert Errors.Deposit_InvalidNonce();
        if (blockId != block.chainid) revert Errors.Deposit_InvalidChain();
    }

    function validateAccountAssetPolicy(
        AssetPolicy memory policy,
        BrokerAccountInfo memory account,
        bool isDeposit
    ) internal view {
        if (!isActive(account)) revert Errors.Deposit_AccountNotActive();

        if (isExpired(account) && isDeposit) {
            revert Errors.Deposit_AccountExpired();
        }

        if (
            (!policy.canDeposit && isDeposit) || (!policy.canWithdraw && !isDeposit)
                || !policy.enabled
        ) {
            revert Errors.Deposit_AssetUnavailable();
        }

        if (policy.permissioned && !isSuperUser(account)) {
            revert Errors.Deposit_OnlySuperUser();
        }
    }

    function isActive(BrokerAccountInfo memory account) internal pure returns (bool) {
        return account.state == AccountState.ACTIVE;
    }

    function isPaused(BrokerAccountInfo memory account) internal pure returns (bool) {
        return account.state == AccountState.PAUSED;
    }

    function canBeClosed(BrokerAccountInfo memory account) internal pure returns (bool) {
        return account.state == AccountState.ACTIVE || account.state == AccountState.PAUSED;
    }

    function isSuperUser(BrokerAccountInfo memory account) internal pure returns (bool) {
        return account.role == Role.SUPER_USER;
    }

    function isExpired(BrokerAccountInfo memory account) internal view returns (bool) {
        return account.expirationTimestamp != 0 && block.timestamp >= account.expirationTimestamp;
    }
}
