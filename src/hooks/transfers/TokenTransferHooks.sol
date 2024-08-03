// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IBeforeTransaction} from "@src/interfaces/ITransactionHooks.sol";
import "@openzeppelin-contracts/interfaces/IERC20.sol";
import "@src/libs/Errors.sol";
import "@src/hooks/BaseHook.sol";
import "@src/libs/Constants.sol";

library TransferWhitelistLib {
    function pointer(address token, address recipient, address sender, bytes4 selector)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(token, recipient, sender, selector));
    }

    function contains(
        mapping(bytes32 => bool) storage transferWhitelist,
        address token,
        address recipient,
        address sender,
        bytes4 selector
    ) internal view returns (bool) {
        return transferWhitelist[pointer(token, recipient, sender, selector)];
    }

    function add(
        mapping(bytes32 => bool) storage transferWhitelist,
        address token,
        address recipient,
        address sender,
        bytes4 selector
    ) internal {
        transferWhitelist[pointer(token, recipient, sender, selector)] = true;
    }

    function remove(
        mapping(bytes32 => bool) storage transferWhitelist,
        address token,
        address recipient,
        address sender,
        bytes4 selector
    ) internal {
        transferWhitelist[pointer(token, recipient, sender, selector)] = false;
    }
}

error TokenTransferHooks_TransferNotAllowed();

error TokenTransferHooks_DataMustBeEmpty();

event TokenTransferHooks_TransferEnabled(
    address token, address recipient, address sender, bytes4 selector
);

event TokenTransferHooks_TransferDisabled(
    address token, address recipient, address sender, bytes4 selector
);

bytes4 constant NATIVE_ETH_TRANSFER_SELECTOR = bytes4(0);

contract TokenTransferHooks is BaseHook, IBeforeTransaction {
    using TransferWhitelistLib for mapping(bytes32 => bool);

    /// @dev pointer = keccak256(abi.encode(token, recipient, sender, selector))
    mapping(bytes32 pointer => bool enabled) private transferWhitelist;

    constructor(address _fund) BaseHook(_fund) {}

    function checkBeforeTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256 value,
        bytes calldata data
    ) external view override onlyFund expectOperation(operation, CALL) {
        if (selector == IERC20.transfer.selector) {
            /// decode the recipient and amount from the data
            (address recipient, uint256 _amount) = abi.decode(data, (address, uint256));

            /// transfer must go to an authorized recipient
            if (!transferWhitelist.contains(target, recipient, address(fund), selector)) {
                revert TokenTransferHooks_TransferNotAllowed();
            }
        } else if (selector == IERC20.transferFrom.selector) {
            /// decode the sender, recipient and amount from the data
            (address sender, address recipient, uint256 _amount) =
                abi.decode(data, (address, address, uint256));

            /// transfer must go to an authorized recipient
            if (!transferWhitelist.contains(target, recipient, sender, selector)) {
                revert TokenTransferHooks_TransferNotAllowed();
            }
        } else if (selector == NATIVE_ETH_TRANSFER_SELECTOR) {
            if (value == 0) revert Errors.Hook_InvalidValue();
            if (data.length > 0) revert TokenTransferHooks_DataMustBeEmpty();

            /// @notice the target is the recipient of the native asset (eth)
            if (!transferWhitelist.contains(NATIVE_ASSET, target, address(fund), selector)) {
                revert TokenTransferHooks_TransferNotAllowed();
            }
        } else {
            revert Errors.Hook_InvalidTargetSelector();
        }
    }

    function enableTransfer(address token, address recipient, address sender, bytes4 selector)
        external
        onlyFund
    {
        if (
            selector != IERC20.transfer.selector && selector != IERC20.transferFrom.selector
                && selector != NATIVE_ETH_TRANSFER_SELECTOR
        ) {
            revert Errors.Hook_InvalidTargetSelector();
        }

        transferWhitelist.add(token, recipient, sender, selector);

        emit TokenTransferHooks_TransferEnabled(token, recipient, sender, selector);
    }

    function disableTransfer(address token, address recipient, address sender, bytes4 selector)
        external
        onlyFund
    {
        transferWhitelist.remove(token, recipient, sender, selector);

        emit TokenTransferHooks_TransferDisabled(token, recipient, sender, selector);
    }

    function isTransferEnabled(address token, address recipient, address sender, bytes4 selector)
        external
        view
        returns (bool)
    {
        return transferWhitelist.contains(token, recipient, sender, selector);
    }
}
