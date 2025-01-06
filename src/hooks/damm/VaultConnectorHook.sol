// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseHook} from "@src/hooks/BaseHook.sol";
import {IBeforeTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {IPeriphery} from "@src/interfaces/IPeriphery.sol";
import {Errors} from "@src/libs/Errors.sol";
import {DepositOrder, WithdrawOrder} from "@src/modules/deposit/Structs.sol";
import {CALL} from "@src/libs/Constants.sol";

error VaultConnectorHook_InvalidRecipient();
error VaultConnectorHook_InvalidAccount();

event VaultConnectorHook_AccountEnabled(address periphery, uint256 accountId);

event VaultConnectorHook_AccountDisabled(address periphery, uint256 accountId);

/// This hook is used to deposit assets from one vault into another
/// So it interacts with the periphery to deposit assets into the vault
contract VaultConnectorHook is BaseHook, IBeforeTransaction {
    /// @dev accountId = keccak256(abi.encode(periphery, accountId))
    mapping(bytes32 accountId => bool allowed) private accountWhitelist;

    constructor(address _fund) BaseHook(_fund) {}

    function checkBeforeTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256,
        bytes calldata data
    ) external view override onlyFund expectOperation(operation, CALL) {
        bytes32 accountId;
        address recipient;

        if (selector == IPeriphery.deposit.selector) {
            DepositOrder memory depositOrder = abi.decode(data, (DepositOrder));
            accountId = _accountPointer(target, depositOrder.accountId);
            recipient = depositOrder.recipient;
        } else if (selector == IPeriphery.withdraw.selector) {
            WithdrawOrder memory withdrawOrder = abi.decode(data, (WithdrawOrder));
            accountId = _accountPointer(target, withdrawOrder.accountId);
            recipient = withdrawOrder.to;
        } else {
            revert Errors.Hook_InvalidTargetSelector();
        }

        if (!accountWhitelist[accountId]) {
            revert VaultConnectorHook_InvalidAccount();
        }

        if (recipient != address(fund)) {
            revert VaultConnectorHook_InvalidRecipient();
        }
    }

    function enableAccount(address periphery, uint256 id) external onlyFund {
        bytes32 accountId = _accountPointer(periphery, id);
        accountWhitelist[accountId] = true;

        emit VaultConnectorHook_AccountEnabled(periphery, id);
    }

    function disableAccount(address periphery, uint256 id) external onlyFund {
        bytes32 accountId = _accountPointer(periphery, id);
        accountWhitelist[accountId] = false;

        emit VaultConnectorHook_AccountDisabled(periphery, id);
    }

    function isAccountEnabled(address periphery, uint256 id) external view returns (bool) {
        return accountWhitelist[_accountPointer(periphery, id)];
    }

    function _accountPointer(address periphery, uint256 accountId)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(periphery, accountId));
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IBeforeTransaction).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
