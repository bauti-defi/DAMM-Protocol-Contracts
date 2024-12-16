// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseHook} from "@src/hooks/BaseHook.sol";
import {IBeforeTransaction, IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {Errors} from "@src/libs/Errors.sol";
import "@gmx/callback/IOrderCallbackReceiver.sol";
import {IExchangeRouter, IBaseOrderUtils} from "@gmx/router/IExchangeRouter.sol";
import "@src/libs/Constants.sol";

error GMXPerpHook_InvalidSelector();
error GMXPerpHook_InvalidTarget();
error GMXPerpHook_InvalidInteraction();
error GMXPerpHook_InvalidCaller();
error GMXPerpHook_UnsupportedAction();
error GMXPerpHook_InvalidOrderReceiver();
error GMXPerpHook_InvalidOrderCancellationReceiver();
error GMXPerpHook_InvalidCallbackContract();

event GMXPerpHook_GmxInteractionEnabled(
    address market,
    address initialCollateralToken,
    address[] swapPath,
    Order.OrderType orderType,
    bool shouldUnwrapNativeToken,
    bool isLong,
    bytes32 interactionIdentifier
);

event GMXPerpHook_GmxInteractionDisabled(bytes32 interactionIdentifier);

/// @dev possible updateOrder params:
/// - key

/// @dev possible cancelOrder params:
/// - key

contract GMXPerpHook is BaseHook, IBeforeTransaction, IAfterTransaction, IOrderCallbackReceiver {
    mapping(bytes32 key => bool enabled) public gmxInteractionWhitelist;
    address public immutable gmxRouter;
    address public immutable gmxOrderHandler;

    constructor(address _fund, address _gmxRouter, address _gmxOrderHandler) BaseHook(_fund) {
        gmxRouter = _gmxRouter;
        gmxOrderHandler = _gmxOrderHandler;
    }

    modifier onlyGmxOrderHandler() {
        if (msg.sender != gmxOrderHandler) {
            revert GMXPerpHook_InvalidCaller();
        }
        _;
    }

    function checkBeforeTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256,
        bytes calldata data
    ) external view override onlyFund expectOperation(operation, CALL) {
        if (target != gmxRouter) {
            revert GMXPerpHook_InvalidTarget();
        }

        if (selector == IExchangeRouter.createOrder.selector) {
            _validateCreateOrder(data);
        } else if (selector == IExchangeRouter.cancelOrder.selector) {
            _validateCancelOrder(data);
        } else if (selector == IExchangeRouter.updateOrder.selector) {
            _validateUpdateOrder(data);
        } else {
            revert GMXPerpHook_InvalidSelector();
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
        if (selector == IExchangeRouter.createOrder.selector) {
            bytes32 key = abi.decode(returnData, (bytes32));
            fund.onPositionOpened(_positionPointer(key));
        }
    }

    function afterOrderExecution(bytes32 key, Order.Props memory, EventUtils.EventLogData memory)
        external
        override
        onlyGmxOrderHandler
    {
        fund.onPositionOpened(_positionPointer(key));
    }

    function afterOrderCancellation(bytes32 key, Order.Props memory, EventUtils.EventLogData memory)
        external
        override
        onlyGmxOrderHandler
    {
        fund.onPositionClosed(_positionPointer(key));
    }

    function afterOrderFrozen(bytes32, Order.Props memory, EventUtils.EventLogData memory)
        external
        override
    {
        revert GMXPerpHook_UnsupportedAction();
    }

    function _positionPointer(bytes32 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, type(IExchangeRouter).interfaceId));
    }

    /// @dev possible CreateOrderParams config settings:
    /// - addresses.callbackContract
    /// - addresses.market
    /// - addresses.initialCollateralToken
    /// - orderType
    /// - addresses.swapPath
    /// - shouldUnwrapNativeToken
    /// - isLong
    function _gmxInteractionIdentifier(
        address market,
        address initialCollateralToken,
        address[] memory swapPath,
        Order.OrderType orderType,
        bool shouldUnwrapNativeToken,
        bool isLong
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                market, initialCollateralToken, swapPath, orderType, shouldUnwrapNativeToken, isLong
            )
        );
    }

    function _validateCreateOrder(bytes calldata data) internal view {
        IBaseOrderUtils.CreateOrderParams memory params =
            abi.decode(data, (IBaseOrderUtils.CreateOrderParams));

        if (params.addresses.receiver != address(fund)) {
            revert GMXPerpHook_InvalidOrderReceiver();
        }

        if (params.addresses.cancellationReceiver != address(fund)) {
            revert GMXPerpHook_InvalidOrderCancellationReceiver();
        }

        if (params.addresses.callbackContract != address(this)) {
            revert GMXPerpHook_InvalidCallbackContract();
        }

        bytes32 interactionIdentifier = _gmxInteractionIdentifier(
            params.addresses.market,
            params.addresses.initialCollateralToken,
            params.addresses.swapPath,
            params.orderType,
            params.shouldUnwrapNativeToken,
            params.isLong
        );

        if (!gmxInteractionWhitelist[interactionIdentifier]) {
            revert GMXPerpHook_InvalidInteraction();
        }
    }

    function _validateCancelOrder(bytes calldata data) internal view {
        bytes32 key = abi.decode(data, (bytes32));

        if (!fund.holdsPosition(_positionPointer(key))) {
            revert GMXPerpHook_InvalidInteraction();
        }
    }

    function _validateUpdateOrder(bytes calldata data) internal view {
        bytes32 key = abi.decode(data, (bytes32));

        if (!fund.holdsPosition(_positionPointer(key))) {
            revert GMXPerpHook_InvalidInteraction();
        }
    }

    function enableGmxInteraction(
        address market,
        address initialCollateralToken,
        address[] memory swapPath,
        Order.OrderType orderType,
        bool shouldUnwrapNativeToken,
        bool isLong
    ) external onlyFund {
        bytes32 interactionIdentifier = _gmxInteractionIdentifier(
            market, initialCollateralToken, swapPath, orderType, shouldUnwrapNativeToken, isLong
        );

        gmxInteractionWhitelist[interactionIdentifier] = true;

        emit GMXPerpHook_GmxInteractionEnabled(
            market,
            initialCollateralToken,
            swapPath,
            orderType,
            shouldUnwrapNativeToken,
            isLong,
            interactionIdentifier
        );
    }

    function disableGmxInteraction(bytes32 interactionIdentifier) external onlyFund {
        gmxInteractionWhitelist[interactionIdentifier] = false;

        emit GMXPerpHook_GmxInteractionDisabled(interactionIdentifier);
    }
}
