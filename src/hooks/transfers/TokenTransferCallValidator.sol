// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IBeforeTransaction} from "@src/interfaces/ITransactionHooks.sol";
import "@openzeppelin-contracts/interfaces/IERC20.sol";
import "@src/libs/Errors.sol";
import {BaseHook} from "@src/hooks/BaseHook.sol";
import "@src/libs/Constants.sol";

error TokenTransferCallValidator_TransferNotAllowed();

error TokenTransferCallValidator_DataMustBeEmpty();

event TokenTransferCallValidator_TransferEnabled(
    address token, address recipient, address sender, bytes4 selector
);

event TokenTransferCallValidator_TransferDisabled(
    address token, address recipient, address sender, bytes4 selector
);

bytes4 constant NATIVE_ETH_TRANSFER_SELECTOR = bytes4(0);

contract TokenTransferCallValidator is BaseHook, IBeforeTransaction {
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
            (address recipient,) = abi.decode(data, (address, uint256));

            /// transfer must go to an authorized recipient
            if (
                !transferWhitelist[_pointer(
                    target, recipient, address(fund), IERC20.transfer.selector
                )]
            ) {
                revert TokenTransferCallValidator_TransferNotAllowed();
            }
        } else if (selector == IERC20.transferFrom.selector) {
            /// decode the sender, recipient and amount from the data
            (address sender, address recipient,) = abi.decode(data, (address, address, uint256));

            /// transfer must go to an authorized recipient
            if (
                !transferWhitelist[_pointer(target, recipient, sender, IERC20.transferFrom.selector)]
            ) {
                revert TokenTransferCallValidator_TransferNotAllowed();
            }
        } else if (selector == NATIVE_ETH_TRANSFER_SELECTOR) {
            if (value == 0) revert Errors.Hook_InvalidValue();
            if (data.length > 0) revert TokenTransferCallValidator_DataMustBeEmpty();

            /// @notice the target is the recipient of the native asset (eth)
            if (
                !transferWhitelist[_pointer(
                    NATIVE_ASSET, target, address(fund), NATIVE_ETH_TRANSFER_SELECTOR
                )]
            ) {
                revert TokenTransferCallValidator_TransferNotAllowed();
            }
        } else {
            revert Errors.Hook_InvalidTargetSelector();
        }
    }

    function _pointer(address token, address recipient, address sender, bytes4 selector)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(token, recipient, sender, selector));
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

        transferWhitelist[_pointer(token, recipient, sender, selector)] = true;

        emit TokenTransferCallValidator_TransferEnabled(token, recipient, sender, selector);
    }

    function disableTransfer(address token, address recipient, address sender, bytes4 selector)
        external
        onlyFund
    {
        transferWhitelist[_pointer(token, recipient, sender, selector)] = false;

        emit TokenTransferCallValidator_TransferDisabled(token, recipient, sender, selector);
    }

    function isTransferEnabled(address token, address recipient, address sender, bytes4 selector)
        external
        view
        returns (bool)
    {
        return transferWhitelist[_pointer(token, recipient, sender, selector)];
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IBeforeTransaction).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
