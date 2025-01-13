// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {
    DepositOrder,
    SignedDepositIntent,
    WithdrawOrder,
    SignedWithdrawIntent,
    AccountLib,
    BrokerAccountInfo
} from "./Structs.sol";
import {IPeriphery} from "@src/interfaces/IPeriphery.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";
import {Errors} from "@src/libs/Errors.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@solmate/tokens/ERC20.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";

event AccountSet(uint256 accountId);
event Paused();
event Unpaused();

/// @dev A module that when added to a gnosis safe, allows for anyone to deposit into the fund
/// the gnosis safe must have a valid broker account (nft) with the periphery to be able to deposit
/// on behalf of the caller.
contract PermissionlessDepositModule {
    using AccountLib for BrokerAccountInfo;
    using SafeTransferLib for ERC20;
    using MessageHashUtils for bytes;

    IPeriphery public immutable periphery;
    ISafe public immutable safe;

    /// @dev do we want this to be mutable?
    uint256 public accountId;
    mapping(address user => uint256 nonce) public nonces;
    bool public paused;

    modifier onlySafe() {
        require(msg.sender == address(safe), "Only safe can call this function");
        _;
    }

    modifier notPaused() {
        if (paused) revert Errors.Deposit_ModulePaused();
        _;
    }

    constructor(address safe_, address periphery_) {
        safe = ISafe(safe_);
        periphery = IPeriphery(periphery_);
    }

    function setAccount(uint256 accountId_) external onlySafe {
        if (IERC721(address(periphery)).ownerOf(accountId_) != address(safe)) {
            revert Errors.Deposit_OnlyAccountOwner();
        }

        BrokerAccountInfo memory account = periphery.getAccountInfo(accountId_);

        if (!account.isActive()) {
            revert Errors.Deposit_AccountNotActive();
        }

        accountId = accountId_;

        emit AccountSet(accountId_);
    }

    function deposit(DepositOrder calldata order) external notPaused returns (uint256 sharesOut) {
        if (accountId != order.accountId) {
            revert Errors.Deposit_InvalidAccountId();
        }

        ERC20(order.asset).safeTransferFrom(msg.sender, address(safe), order.amount);

        sharesOut = periphery.deposit(order);
    }

    function intentDeposit(SignedDepositIntent calldata order)
        external
        notPaused
        returns (uint256 sharesOut)
    {
        if (accountId != order.intent.deposit.accountId) {
            revert Errors.Deposit_InvalidAccountId();
        }

        _validateIntent(
            abi.encode(order.intent), order.signature, order.intent.chaindId, order.intent.nonce
        );

        ERC20(order.intent.deposit.asset).safeTransferFrom(
            msg.sender,
            address(safe),
            order.intent.deposit.amount + order.intent.relayerTip + order.intent.bribe
        );

        sharesOut = periphery.deposit(order.intent.deposit);
    }

    function withdraw(WithdrawOrder calldata order)
        external
        notPaused
        returns (uint256 assetAmountOut)
    {
        if (accountId != order.accountId) {
            revert Errors.Deposit_InvalidAccountId();
        }

        ERC20(periphery.getVault()).safeTransferFrom(msg.sender, address(safe), order.shares);

        assetAmountOut = periphery.withdraw(order);
    }

    function intentWithdraw(SignedWithdrawIntent calldata order)
        external
        notPaused
        returns (uint256 assetAmountOut)
    {
        if (accountId != order.intent.withdraw.accountId) {
            revert Errors.Deposit_InvalidAccountId();
        }

        _validateIntent(
            abi.encode(order.intent), order.signature, order.intent.chaindId, order.intent.nonce
        );

        assetAmountOut = periphery.withdraw(order.intent.withdraw);
    }

    function _validateIntent(
        bytes memory intent,
        bytes memory signature,
        uint256 blockId,
        uint256 nonce
    ) internal {
        if (
            !SignatureChecker.isValidSignatureNow(
                msg.sender, intent.toEthSignedMessageHash(), signature
            )
        ) revert Errors.Deposit_InvalidSignature();

        if (blockId != block.chainid) revert Errors.Deposit_InvalidChain();

        if (nonce != nonces[msg.sender]++) {
            revert Errors.Deposit_InvalidNonce();
        }
    }

    function pause() external onlySafe {
        paused = true;

        emit Paused();
    }

    function unpause() external onlySafe {
        paused = false;

        emit Unpaused();
    }
}
