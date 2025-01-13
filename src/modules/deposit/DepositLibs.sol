// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Errors} from "@src/libs/Errors.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";

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
    ) internal {
        if (
            !SignatureChecker.isValidSignatureNow(signer, intent.toEthSignedMessageHash(), signature)
        ) revert Errors.Deposit_InvalidSignature();
        if (nonce != expectedNonce) revert Errors.Deposit_InvalidNonce();
        if (blockId != block.chainid) revert Errors.Deposit_InvalidChain();
    }
}
