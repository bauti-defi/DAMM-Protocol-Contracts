// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseHook} from "@src/hooks/BaseHook.sol";
import {IBeforeTransaction, IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {Errors} from "@src/libs/Errors.sol";
import "@gmx/callback/IOrderCallbackReceiver.sol";
import {IExchangeRouter} from "@gmx/router/IExchangeRouter.sol";
import "@src/libs/Constants.sol";


error GMXCallValidator_InvalidSelector();


/// @dev possible CreateOrderParams config settings:
/// - addresses.callbackContract
/// - addresses.market
/// - addresses.initialCollateralToken
/// - orderType
/// - isLong

/// @dev possible updateOrder params:
/// - key

/// @dev possible cancelOrder params:
/// - key

contract GMXPerpHook is BaseHook, IBeforeTransaction, IAfterTransaction, IOrderCallbackReceiver {

    constructor(address _fund) BaseHook(_fund) {}

    function checkBeforeTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256,
        bytes calldata data
    ) external view override onlyFund expectOperation(operation, CALL) {
        if (selector != IExchangeRouter.createOrder.selector) {
            revert GMXCallValidator_InvalidSelector();
        }

    }

    function checkAfterTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256,
        bytes calldata data,
        bytes calldata returnData
    ) external override onlyFund expectOperation(operation, CALL) {
        if(selector == IExchangeRouter.createOrder.selector) {
            bytes32 key = abi.decode(returnData, (bytes32));
            fund.onPositionOpened(_positionPointer(key));
        }else if(selector == IExchangeRouter.cancelOrder.selector){
            bytes32 key = abi.decode(data, (bytes32));
            fund.onPositionClosed(_positionPointer(key));
        }
    }

    /// TODO: check the caller is GMX
    function afterOrderExecution(bytes32 key, Order.Props memory order, EventUtils.EventLogData memory eventData) external override {
        fund.onPositionOpened(_positionPointer(key));
    }

    /// TODO: check the caller is GMX
    function afterOrderCancellation(bytes32 key, Order.Props memory order, EventUtils.EventLogData memory eventData) external override {
        fund.onPositionClosed(_positionPointer(key));
    }

    function afterOrderFrozen(bytes32 key, Order.Props memory order, EventUtils.EventLogData memory eventData) external override {
    }

    function _positionPointer(bytes32 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, type(IExchangeRouter).interfaceId));
    }

    /// @dev check the following:
    /// - 
    function _validateCreateOrder(bytes calldata data) internal view {
        
    }
}
